import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor struct HookCardTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-12T20:00:00Z")!
    private func seed() throws -> FeaturedStorySnapshot {
        let url = try #require(Bundle.main.url(forResource: "featured-preview", withExtension: "json"))
        let value = try JSONDecoder().decode(FeaturedStoryPreview.Envelope.self, from: Data(contentsOf: url))
        return FeaturedStorySnapshot(manifest: value.manifest, payload: try #require(Data(base64Encoded: value.payloadBase64)), savedAt: now)
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "hook-test-" + UUID().uuidString)! }
    private func cache() -> FeaturedStoryCache { FeaturedStoryCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)) }
    private func changed(_ entry: StoryEntry, id: String? = nil, revision: String? = nil) -> StoryEntry {
        StoryEntry(id: id ?? entry.id, revision: revision ?? entry.revision, title: entry.title, summary: entry.summary, fallback: entry.fallback, publishedAt: entry.publishedAt, teamIDs: entry.teamIDs, renderer: entry.renderer, rendererVersion: entry.rendererVersion, minimumRendererVersion: entry.minimumRendererVersion)
    }
    @Test func playDismissAndInterruptedPlaybackSurviveColdRelaunch() throws {
        let entry = try #require(seed().manifest.entry)
        for _ in ["Play", "Dismiss", "Swipe dismissal"] {
            let preferences = defaults()
            var launch = FeaturedStoryLaunch(defaults: preferences)
            #expect(launch.offer(completedOnboarding: true, busy: false, entry: entry) != nil)
            launch.acknowledge(entry.id) // The same atomic action is used before Play and by every dismissal route.
            var cold = FeaturedStoryLaunch(defaults: preferences)
            #expect(cold.offer(completedOnboarding: true, busy: false, entry: entry) == nil)
        }
    }
    @Test func stableIdentityIgnoresRevisionChangesAndSuppressesAToBToA() throws {
        let a = try #require(seed().manifest.entry), b = changed(a: try #require(seed().manifest.entry))
        let preferences = defaults()
        var first = FeaturedStoryLaunch(defaults: preferences)
        #expect(first.offer(completedOnboarding: true, busy: false, entry: a) != nil); first.acknowledge(a.id)
        var second = FeaturedStoryLaunch(defaults: preferences)
        #expect(second.offer(completedOnboarding: true, busy: false, entry: b) != nil); second.acknowledge(b.id)
        var rollback = FeaturedStoryLaunch(defaults: preferences)
        #expect(rollback.offer(completedOnboarding: true, busy: false, entry: changed(a, revision: String(repeating: "a", count: 64))) == nil)
    }
    private func changed(a: StoryEntry) -> StoryEntry { changed(a, id: "another-daily-story") }
    @Test func unansweredCardMayReofferButBusyOnboardingAndEmptyDoNotAcknowledge() throws {
        let a = try #require(seed().manifest.entry), preferences = defaults()
        var first = FeaturedStoryLaunch(defaults: preferences)
        #expect(first.offer(completedOnboarding: false, busy: false, entry: a) == nil)
        #expect(first.offer(completedOnboarding: true, busy: true, entry: a) == nil)
        #expect(!first.acknowledged(a.id))
        #expect(first.offer(completedOnboarding: true, busy: false, entry: a) != nil)
        var cold = FeaturedStoryLaunch(defaults: preferences)
        #expect(cold.offer(completedOnboarding: true, busy: false, entry: a) != nil)
    }
    @Test func exactThirdsJapanAndCapabilityFiveAreValidated() throws {
        let saved = try seed(), entry = try #require(saved.manifest.entry)
        guard case .trajectory(let value) = try saved.document(build: 128, now: now) else { Issue.record("Wrong renderer"); return }
        #expect(value.minimumCapability == 5 && !entry.isSupported(by: 4))
        let expectedValues: [Double] = [5.0/3,0,19.0/3,0,0,0,518.0/3]
        let actualValues = value.chart.series[0].points.map(\.y)
        #expect(actualValues == expectedValues)
        #expect(value.presentation?.intervals[0].label == "JAPAN · 2023–25")
        let fractionalValues: [Double] = [5.0/3,19.0/3,518.0/3]
        let labels = fractionalValues.map { TrajectoryNumberPresentation.innings.axis($0) }
        #expect(labels == ["1⅔","6⅓","172⅔"])
        let p = try #require(value.presentation)
        #expect(p.barGrowth(elapsed: 0.9,index: 0,count: 7) == 0)
        #expect(p.barGrowth(elapsed: 1.5,index: 0,count: 7) == 0.5)
        #expect(p.barGrowth(elapsed: 8,index: 6,count: 7) == 1)
        #expect(p.hookIsCurrent(now: now) && !p.hookIsCurrent(now: ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!))
        var object = try #require(JSONSerialization.jsonObject(with: saved.payload) as? [String:Any])
        var presentation = try #require(object["presentation"] as? [String:Any]); presentation["style"] = "remote-html"; object["presentation"] = presentation
        let bad = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { _ = try StoryContract.decodeDocument(bad, entry: changed(entry, revision: StoryContract.hash(bad))) }
    }
    @Test func privateSeedWorksOfflineAndNeverReopensOlderProductionContent() async throws {
        let preview = try seed(), clock = now
        let store = FeaturedStoryStore(cache: cache(), build: 128, clock: { clock }, fetch: { _,_ in throw URLError(.notConnectedToInternet) }, preview: preview, previewDefaults: defaults())
        await store.prepare(); #expect(store.selected()?.entry.id == preview.manifest.entry?.id)
        #expect(store.previewLibraryItem?.entry.id == preview.manifest.entry?.id)
        let late = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!
        let expired = FeaturedStoryStore(cache: cache(), build: 128, clock: { late }, fetch: { _,_ in throw URLError(.notConnectedToInternet) }, preview: preview, previewDefaults: defaults())
        await expired.prepare(); #expect(expired.selected() == nil && expired.previewLibraryItem != nil)
    }
    @Test func newerAuthoritativeDisableRetiresSeedAcrossColdStarts() async throws {
        let preview = try seed(), clock = now, preferences = defaults()
        let disabled = FeaturedStoryManifest(schemaVersion:1, enabled:false, revision:"newer-disable", publishedAt:"2026-10-12T20:00:00Z", notBefore:"2026-10-12T00:00:00Z", expiresAt:"2026-10-13T00:00:00Z", minimumBuild:128, entry:nil)
        let bytes = try JSONEncoder().encode(disabled)
        let first = FeaturedStoryStore(cache: cache(), build:128, clock:{ clock }, fetch:{ _,_ in bytes }, preview:preview, previewDefaults:preferences)
        await first.prepare(); #expect(first.selected() == nil)
        let cold = FeaturedStoryStore(cache: cache(), build:128, clock:{ clock }, fetch:{ _,_ in throw URLError(.notConnectedToInternet) }, preview:preview, previewDefaults:preferences)
        await cold.prepare(); #expect(cold.selected() == nil)
    }
    @Test func badNewerPayloadCannotRetireValidSeed() async throws {
        let preview = try seed(), clock = now, preferences = defaults()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preview.manifest)) as? [String:Any]); object["publishedAt"] = "2026-10-12T20:00:00Z"
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let first = FeaturedStoryStore(cache:cache(), build:128, clock:{ clock }, fetch:{ url,_ in url.lastPathComponent == "featured-v1.json" ? bytes : Data("bad hash".utf8) }, preview:preview, previewDefaults:preferences)
        await first.prepare(); #expect(first.selected()?.entry.id == preview.manifest.entry?.id)
        let cold = FeaturedStoryStore(cache:cache(), build:128, clock:{ clock }, fetch:{ _,_ in throw URLError(.notConnectedToInternet) }, preview:preview, previewDefaults:preferences)
        await cold.prepare(); #expect(cold.selected()?.entry.id == preview.manifest.entry?.id)
    }
    @Test func newerRemoteDocumentSupersedesPrivateSeedAndStaysPinnedOffline() async throws {
        let preview = try seed(), clock = now, preferences = defaults(), slot = cache()
        var object = try #require(JSONSerialization.jsonObject(with: preview.payload) as? [String:Any]);object["id"] = "next-remote-story"
        let payload = try JSONSerialization.data(withJSONObject: object)
        let entry = changed(try #require(preview.manifest.entry), id:"next-remote-story", revision:StoryContract.hash(payload))
        let manifest = FeaturedStoryManifest(schemaVersion:1, enabled:true, revision:"newer-content", publishedAt:"2026-10-12T20:00:00Z", notBefore:"2026-10-12T00:00:00Z", expiresAt:"2026-10-13T00:00:00Z", minimumBuild:128, entry:entry)
        let bytes = try JSONEncoder().encode(manifest)
        let first = FeaturedStoryStore(cache:slot, build:128, clock:{ clock }, fetch:{ url,_ in url.lastPathComponent == "featured-v1.json" ? bytes : payload }, preview:preview, previewDefaults:preferences)
        await first.prepare();let pinned = try #require(first.selected())
        #expect(pinned.entry.id == "next-remote-story" && pinned.entry.revision == StoryContract.hash(payload))
        let cold = FeaturedStoryStore(cache:slot, build:128, clock:{ clock }, fetch:{ _,_ in throw URLError(.notConnectedToInternet) }, preview:preview, previewDefaults:preferences)
        await cold.prepare(); #expect(cold.selected()?.entry.id == "next-remote-story")
    }

}
