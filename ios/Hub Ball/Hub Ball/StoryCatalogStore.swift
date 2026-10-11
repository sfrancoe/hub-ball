import Foundation
import Observation

nonisolated enum StoryContentOrigin {
    static let allowedHosts = ["api.autumnlane.io", "red-sox.netlify.app"]
    static func approved(_ url: URL, debug: Bool = false) -> Bool {
        guard url.user == nil && url.password == nil && url.query == nil && url.fragment == nil else { return false }
        if debug && url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? "") { return true }
        return url.scheme == "https" && allowedHosts.contains(url.host ?? "") && (url.port == nil || url.port == 443)
    }
    static var root: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["HUB_STORY_ROOT"], let url = URL(string: value), approved(url, debug: true) { return url }
        #endif
        let url = AppBackend.sharedDataURL("stories").deletingLastPathComponent()
        return approved(url) ? url : URL(string: "https://red-sox.netlify.app/api/data")!
    }
}

/// Public content never follows redirects into unapproved hosts or login surfaces.
nonisolated final class StoryRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

nonisolated enum StorySeed {
    static var catalog: StoryCatalog {
        #if DEBUG
        if ProcessInfo.processInfo.environment["HUB_STORY_NO_SEED"] == "1" { return .empty }
        #endif
        guard let url = Bundle.main.url(forResource: "story-catalog", withExtension: "json"), let data = try? Data(contentsOf: url),
              let result = try? StoryContract.decodeCatalog(data) else { return .empty }
        return result
    }
    static func payload(_ entry: StoryEntry) -> Data? {
        guard let seed = catalog.stories.first(where: { $0.id == entry.id && $0.revision == entry.revision }),
              let url = Bundle.main.url(forResource: "story-seed-\(seed.id)", withExtension: "json"),
              let data = try? Data(contentsOf: url), (try? StoryContract.decodeDocument(data, entry: seed)) != nil else { return nil }
        return data
    }
}

@MainActor @Observable
final class StoryCatalogStore {
    typealias Fetch = @Sendable (URL, URLRequest.CachePolicy) async throws -> Data
    private(set) var catalog: StoryCatalog
    private(set) var isRefreshing = false
    private(set) var refreshFailed = false
    private(set) var stories: [String: StoryDocument] = [:]
    private(set) var notes: [String: String] = [:]
    private(set) var loading = Set<String>()
    private let cache: StoryContentCache
    private let root: URL
    private let fetch: Fetch
    private let seedPayload: @Sendable (StoryEntry) -> Data?
    private var restored = false
    private var loadedEntries: [String: StoryEntry] = [:]
    private var accesses: [String: Int] = [:]
    private var accessCounter = 0

    init(root: URL = StoryContentOrigin.root, cache: StoryContentCache = StoryContentCache(),
         seed: StoryCatalog = StorySeed.catalog, seedPayload: @escaping @Sendable (StoryEntry) -> Data? = StorySeed.payload,
         fetch: Fetch? = nil) {
        self.root = root; self.cache = cache; self.seedPayload = seedPayload
        catalog = (try? seed.validate()) != nil ? seed : .empty
        if let fetch { self.fetch = fetch }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 4 * 1_024 * 1_024, diskCapacity: 16 * 1_024 * 1_024)
            configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
            let api = APIClient(session: URLSession(configuration: configuration, delegate: StoryRedirectPolicy(), delegateQueue: nil))
            self.fetch = { url, policy in try await api.data(.url(url), cachePolicy: policy) }
        }
    }

    func contentRevision(for id: String) -> String { loadedEntries[id]?.cacheKey ?? id }

    func restore() async {
        guard !restored else { return }
        restored = true
        if let data = await cache.catalog(), let saved = try? StoryContract.decodeCatalog(data) { catalog = saved }
        for entry in catalog.stories.prefix(20) {
            if let cached = await cache.story(id: entry.id) { remember(cached, note: "Saved for offline reading") }
            else if let data = seedPayload(entry) { remember(CachedStory(entry: entry, data: data), note: nil) }
        }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await restore()
        do {
            let data = try await fetch(root.appending(path: "stories/catalog-v1.json"), force ? .reloadIgnoringLocalCacheData : .reloadRevalidatingCacheData)
            try Task.checkCancellation()
            let incoming = try StoryContract.decodeCatalog(data)
            catalog = incoming; refreshFailed = false
            // A rollback may point to any earlier immutable payload; publication order is authoritative.
            let activeIDs = Set(incoming.stories.map(\.id))
            stories = stories.filter { activeIDs.contains($0.key) }; notes = notes.filter { activeIDs.contains($0.key) }
            loadedEntries = loadedEntries.filter { activeIDs.contains($0.key) }
            accesses = accesses.filter { activeIDs.contains($0.key) }
            await cache.saveCatalog(data)
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            refreshFailed = true
        }
    }

    func load(_ entry: StoryEntry, force: Bool = false) async {
        guard entry.isSupported, !loading.contains(entry.id) else { return }
        loading.insert(entry.id)
        defer { loading.remove(entry.id) }
        await restore()
        if loadedEntries[entry.id]?.revision == entry.revision && !force { touch(entry.id); return }
        if let saved = await cache.story(id: entry.id) { remember(saved, note: "Saved for offline reading") }
        if let data = seedPayload(entry) {
            remember(CachedStory(entry: entry, data: data), note: nil)
            await cache.saveStory(CachedStory(entry: entry, data: data))
            if !force { return }
        }
        do {
            let data = try await fetch(root.appending(path: entry.payloadPath), force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad)
            try Task.checkCancellation()
            let cached = CachedStory(entry: entry, data: data)
            let value = try cached.decoded()
            stories[entry.id] = value; loadedEntries[entry.id] = entry; notes[entry.id] = nil
            touch(entry.id)
            await cache.saveStory(cached)
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            notes[entry.id] = stories[entry.id] == nil ? "This story couldn’t be downloaded. Try again when connected." : "Showing the last verified version. The update couldn’t be downloaded."
        }
    }

    private func remember(_ cached: CachedStory, note: String?) {
        guard let value = try? cached.decoded() else { return }
        stories[cached.entry.id] = value; loadedEntries[cached.entry.id] = cached.entry; notes[cached.entry.id] = note
        touch(cached.entry.id)
    }
    private func touch(_ id: String) {
        accessCounter += 1; accesses[id] = accessCounter
        while accesses.count > 20 {
            guard let oldest = accesses.min(by: { $0.value < $1.value })?.key else { break }
            accesses[oldest] = nil; stories[oldest] = nil; loadedEntries[oldest] = nil; notes[oldest] = nil
        }
    }
}
