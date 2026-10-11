import Foundation
import Observation
import SwiftUI

/// A finite pointer to bundled renderers, never HTML, script, or a remote URL.
nonisolated struct FeaturedStoryManifest: Codable, Sendable {
    let schemaVersion: Int
    let enabled: Bool
    let revision: String
    let publishedAt: String
    let notBefore: String
    let expiresAt: String
    let minimumBuild: Int
    let entry: StoryEntry?
    static let limit = 16 * 1_024
    func validate() throws {
        guard schemaVersion == 1 else { throw StoryContentError.unsupported }
        try StoryContract.check(StoryContract.slug(revision) && (1...1_000_000).contains(minimumBuild))
        for value in [publishedAt, notBefore, expiresAt] { try StoryContract.check(StoryContract.timestamp(value)) }
        let dates = ISO8601DateFormatter()
        let start = dates.date(from: notBefore)!, end = dates.date(from: expiresAt)!
        try StoryContract.check(end > start && end.timeIntervalSince(start) <= 7 * 86400 && dates.date(from: publishedAt)! <= end)
        try StoryContract.check(enabled ? entry != nil : entry == nil)
        try entry?.validate()
    }
    func eligible(build: Int, capability: Int = StoryContract.rendererVersion, now: Date) -> Bool {
        let dates = ISO8601DateFormatter()
        return enabled && minimumBuild <= build && entry?.isSupported(by: capability) == true &&
            now >= (dates.date(from: notBefore) ?? .distantFuture) && now < (dates.date(from: expiresAt) ?? .distantPast)
    }
    static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= limit else { throw StoryContentError.oversized }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        try value.validate(); return value
    }
}

nonisolated struct FeaturedStorySnapshot: Codable, Sendable {
    let manifest: FeaturedStoryManifest
    let payload: Data
    let savedAt: Date
    func document(build: Int, now: Date) throws -> StoryDocument {
        try manifest.validate()
        try StoryContract.check(manifest.eligible(build: build, now: now) && now >= savedAt && now.timeIntervalSince(savedAt) <= 86400)
        guard let entry = manifest.entry else { throw StoryContentError.invalid }
        return try StoryContract.decodeDocument(payload, entry: entry)
    }
}

/// One atomic verified slot; content remains usable for at most 24 hours and never beyond expiry.
actor FeaturedStoryCache {
    private let url: URL
    init(directory: URL? = nil) {
        var name = "Featured"
        #if DEBUG
        if let suffix = ProcessInfo.processInfo.environment["HUB_FEATURED_CACHE_NAME"], StoryContract.slug(suffix) { name += "-" + suffix }
        #endif
        url = (directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "HubBall/\(name)"))
            .appending(path: "verified.json")
    }
    func read() -> FeaturedStorySnapshot? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 750 * 1_024, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeaturedStorySnapshot.self, from: data)
    }
    func save(_ value: FeaturedStorySnapshot) {
        guard let data = try? JSONEncoder().encode(value), data.count <= 750 * 1_024 else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { /* Optional cache must not interrupt launch. */ }
    }
    func clear() { try? FileManager.default.removeItem(at: url) }
}

@MainActor @Observable final class FeaturedStoryStore {
    typealias Fetch = StoryCatalogStore.Fetch
    private let root: URL
    private let cache: FeaturedStoryCache
    private let build: Int
    private let fetch: Fetch
    private let clock: @Sendable () -> Date
    private var snapshot: FeaturedStorySnapshot?
    private(set) var prepared = false
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var completion: CheckedContinuation<Void, Never>?
    private var started = false

    init(root: URL = FeaturedStoryStore.liveRoot, cache: FeaturedStoryCache = FeaturedStoryCache(),
         build: Int = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
         clock: @escaping @Sendable () -> Date = Date.init, fetch: Fetch? = nil) {
        self.root = root; self.cache = cache; self.build = build; self.clock = clock
        if let fetch { self.fetch = fetch }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 15
            let client = APIClient(session: URLSession(configuration: configuration, delegate: StoryRedirectPolicy(), delegateQueue: nil))
            self.fetch = { url, policy in try await client.data(.url(url), cachePolicy: policy) }
        }
    }
    static var liveRoot: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_FEATURED_ROOT"], let url = URL(string: value), StoryContentOrigin.approved(url, debug: true) { return url }
        #endif
        // Independent of library visibility and Debug team-feed overrides.
        return URL(string: "https://api.autumnlane.io/api/data")!
    }
    func selected() -> FeaturedStoryItem? {
        guard let snapshot, let entry = snapshot.manifest.entry,
              let document = try? snapshot.document(build: build, now: clock()) else { return nil }
        return FeaturedStoryItem(entry: entry, document: document)
    }
    func prepare(timeout: Duration = .seconds(2)) async {
        guard !started else { return }
        started = true
        if let saved = await cache.read(), (try? saved.document(build: build, now: clock())) != nil { snapshot = saved }
        await withCheckedContinuation { continuation in
            completion = continuation
            requestTask = Task { [weak self] in await self?.refresh() }
            deadlineTask = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish()
            }
        }
    }
    private func refresh() async {
        do {
            guard StoryContentOrigin.approved(root, debug: _isDebugAssertConfiguration()) else { throw URLError(.badURL) }
            let bytes = try await fetch(root.appending(path: "stories/featured-v1.json"), .reloadIgnoringLocalAndRemoteCacheData)
            try Task.checkCancellation()
            guard !prepared else { return }
            let manifest = try FeaturedStoryManifest.decode(bytes)
            // A valid authoritative disable/expiry/compatibility decision revokes saved launch content.
            guard manifest.eligible(build: build, now: clock()), let entry = manifest.entry else {
                snapshot = nil; await cache.clear(); finish(); return
            }
            let payload = try await fetch(root.appending(path: entry.payloadPath), .returnCacheDataElseLoad)
            try Task.checkCancellation()
            guard !prepared else { return }
            let incoming = FeaturedStorySnapshot(manifest: manifest, payload: payload, savedAt: clock())
            _ = try incoming.document(build: build, now: clock())
            snapshot = incoming
            await cache.save(incoming)
            finish()
        } catch {
            if !Task.isCancelled { finish() } // Invalid bytes or failed network retain only the compatible verified slot.
        }
    }
    private func finish() {
        guard !prepared else { return }
        prepared = true
        requestTask?.cancel(); deadlineTask?.cancel()
        completion?.resume(); completion = nil
    }
}

nonisolated struct FeaturedStoryItem: Identifiable, Sendable {
    let entry: StoryEntry
    let document: StoryDocument
    var id: String { entry.cacheKey }
}

/// The exact downloaded revision is pinned for this presentation; IDs never select bundled content.
struct FeaturedStoryDocumentView: View {
    let item: FeaturedStoryItem
    let close: () -> Void
    var body: some View {
        NavigationStack {
            Group {
                switch item.document {
                case .outGrid(let value): InningOutGridStoryView(story: value, close: close, onCompleted: close)
                case .trajectory(let value):
                    TrajectoryStoryView(story: value, refresh: {}, onCompleted: close)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Dismiss", action: close).accessibilityIdentifier("featured.close") } }
                case .guess(let value):
                    GuessRevealStoryView(story: value, refresh: {})
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Dismiss", action: close).accessibilityIdentifier("featured.close") } }
                }
            }
        }
        .accessibilityIdentifier("featured.document.\(item.entry.id)")
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
