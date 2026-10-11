import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor struct FeaturedStoryTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T16:00:00Z")!
    private func fixture(enabled: Bool = true, minimumBuild: Int = 127, expiry: String = "2026-10-12T00:00:00Z", entry: StoryEntry? = nil) throws -> (FeaturedStoryManifest, Data) {
        let item = try #require(ClevelandLaunchStory.item)
        let url = try #require(Bundle.main.url(forResource: "story-private-cleveland-k", withExtension: "json"))
        return (FeaturedStoryManifest(schemaVersion: 1, enabled: enabled, revision: "test-opening", publishedAt: "2026-10-11T00:00:00Z", notBefore: "2026-10-11T00:00:00Z", expiresAt: expiry, minimumBuild: minimumBuild, entry: enabled ? entry ?? item.entry : nil), try Data(contentsOf: url))
    }
    private func cache() -> FeaturedStoryCache { FeaturedStoryCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)) }
    @Test func dateBuildCapabilityAndStructuralGates() throws {
        let (manifest, _) = try fixture()
        try manifest.validate()
        #expect(manifest.eligible(build: 127, now: now))
        #expect(!manifest.eligible(build: 126, now: now) && !manifest.eligible(build: 127, capability: 3, now: now))
        #expect(!manifest.eligible(build: 127, now: now.addingTimeInterval(86400)))
        #expect(!manifest.eligible(build: 127, now: now.addingTimeInterval(-86400)))
        #expect(throws: (any Error).self) { _ = try FeaturedStoryManifest.decode(Data(repeating: 32, count: FeaturedStoryManifest.limit + 1)) }
        let (tooLong, _) = try fixture(expiry: "2026-10-20T00:00:00Z")
        #expect(throws: (any Error).self) { try tooLong.validate() }
    }
    @Test func exactRevisionAndCommentaryComeFromDownloadedBytes() async throws {
        let (first, payload) = try fixture(); let now = now
        var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object["heading"] = "Remote revision"
        object["commentary"] = "This commentary came from the downloaded revision."
        let bytes = try JSONSerialization.data(withJSONObject: object), old = try #require(first.entry)
        let entry = StoryEntry(id: old.id, revision: StoryContract.hash(bytes), title: old.title, summary: old.summary, fallback: old.fallback, publishedAt: old.publishedAt, teamIDs: old.teamIDs, renderer: old.renderer, rendererVersion: old.rendererVersion, minimumRendererVersion: old.minimumRendererVersion)
        let (manifest, _) = try fixture(entry: entry); let pointer = try JSONEncoder().encode(manifest)
        let store = FeaturedStoryStore(cache: cache(), build: 127, clock: { now }, fetch: { url, policy in
            if url.lastPathComponent == "featured-v1.json" { #expect(policy == .reloadIgnoringLocalAndRemoteCacheData); return pointer }
            #expect(url.path.hasSuffix(entry.payloadPath)); return bytes
        })
        await store.prepare()
        guard case .outGrid(let document) = try #require(store.selected()).document else { Issue.record("Wrong renderer"); return }
        #expect(document.heading == "Remote revision" && document.commentary == "This commentary came from the downloaded revision.")
    }
    @Test func offlineCacheIsVerifiedBoundedAndExpires() async throws {
        let (manifest, payload) = try fixture(); let cache = cache(), now = now
        await cache.save(FeaturedStorySnapshot(manifest: manifest, payload: payload, savedAt: now.addingTimeInterval(-100)))
        let store = FeaturedStoryStore(cache: cache, build: 127, clock: { now }, fetch: { _,_ in throw URLError(.notConnectedToInternet) })
        await store.prepare(); #expect(store.selected()?.entry.id == "almost-every-out-a-k")
        for savedAt in [now.addingTimeInterval(-86401), now.addingTimeInterval(1)] {
            await cache.save(FeaturedStorySnapshot(manifest: manifest, payload: payload, savedAt: savedAt))
            let off = FeaturedStoryStore(cache: cache, build: 127, clock: { now }, fetch: { _,_ in throw URLError(.notConnectedToInternet) })
            await off.prepare(); #expect(off.selected() == nil)
        }
        await cache.save(FeaturedStorySnapshot(manifest: manifest, payload: Data("forged".utf8), savedAt: now))
        let corrupt = FeaturedStoryStore(cache: cache, build: 127, clock: { now }, fetch: { _,_ in throw URLError(.notConnectedToInternet) })
        await corrupt.prepare(); #expect(corrupt.selected() == nil)
    }
    @Test func disabledExpiredAndUnsupportedRevokeVerifiedCache() async throws {
        let (good, payload) = try fixture(); let now = now
        for manifest in [try fixture(enabled: false).0, try fixture(minimumBuild: 128).0, try fixture(expiry: "2026-10-11T01:00:00Z").0] {
            let cache = cache(); await cache.save(FeaturedStorySnapshot(manifest: good, payload: payload, savedAt: now))
            let bytes = try JSONEncoder().encode(manifest)
            let store = FeaturedStoryStore(cache: cache, build: 127, clock: { now }, fetch: { url,_ in
                #expect(url.lastPathComponent == "featured-v1.json"); return bytes
            })
            await store.prepare(); #expect(store.selected() == nil)
            #expect(await cache.read() == nil)
        }
    }
    @Test func badHashKeepsOnlyCompatiblePreviousSnapshotAndEmptySkips() async throws {
        let (manifest, payload) = try fixture(); let pointer = try JSONEncoder().encode(manifest), now = now
        for saved in [true, false] {
            let cache = cache()
            if saved { await cache.save(FeaturedStorySnapshot(manifest: manifest, payload: payload, savedAt: now)) }
            let store = FeaturedStoryStore(cache: cache, build: 127, clock: { now }, fetch: { url,_ in url.lastPathComponent == "featured-v1.json" ? pointer : Data("bad hash".utf8) })
            await store.prepare(); #expect((store.selected() != nil) == saved)
        }
    }
    @Test func uncooperativeLateFetchCannotReopenFinishedLaunch() async throws {
        let (manifest, payload) = try fixture(); let pointer = try JSONEncoder().encode(manifest), now = now
        let featured = FeaturedStoryStore(cache: cache(), build: 127, clock: { now }, fetch: { url,_ in
            await withCheckedContinuation { continuation in DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() } }
            return url.lastPathComponent == "featured-v1.json" ? pointer : payload
        })
        let disabled = try JSONEncoder().encode(BetaReleaseManifest(schemaVersion: 1, bundleID: "com.sfrancoe.HubBall", enabled: false, target: nil))
        let updates = BetaUpdateStore(installed: InstalledBeta(version: "1.1", build: 127, os: "26.5", deviceFamily: "iphone"), eligibility: { false }, fetch: { disabled })
        let flow = PostseasonLaunchFlow(); flow.begin(updates: updates, featured: featured, timeout: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(30)); #expect(flow.phase == .ready && featured.prepared && featured.selected() == nil)
        flow.storyDismissed(); try await Task.sleep(for: .milliseconds(130))
        flow.setActive(false); flow.setActive(true)
        #expect(flow.phase == .finished && featured.selected() == nil)
    }
}
