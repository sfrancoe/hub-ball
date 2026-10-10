import Foundation
import Testing
@testable import Hub_Ball

private actor BetaFixture {
    var bytes = Data()
    var failure = false
    var hits = 0
    func set(_ data: Data, fail: Bool = false) { bytes = data; failure = fail }
    func load() throws -> Data { hits += 1; if failure { throw URLError(.notConnectedToInternet) }; return bytes }
}

@Suite(.serialized) @MainActor struct BetaUpdateTests {
    private let now = Date(timeIntervalSince1970: 1_791_635_400)
    private func payload(version: String = "1.1", build: Int = 124, audience: String = "all-supported-testers", confirmed: String? = nil,
                         expiry: String? = nil, minimum: String = "17.0", groups: [String] = Array(BetaRelease.supportedGroups)) throws -> Data {
        let date = ISO8601DateFormatter()
        let target = BetaRelease(version: version, build: build, audience: audience, available: true,
                                 confirmedAt: confirmed ?? date.string(from: now), expiresAt: expiry ?? date.string(from: now.addingTimeInterval(86400)),
                                 minimumOS: minimum, deviceFamilies: ["iphone","ipad"], verifiedGroupIDs: groups)
        return try JSONEncoder().encode(BetaReleaseManifest(schemaVersion: 1, bundleID: "com.sfrancoe.HubBall", enabled: true, target: target))
    }
    private func installed(version: String = "1.1", build: Int = 123, os: String = "26.5") -> InstalledBeta {
        InstalledBeta(version: version, build: build, os: os, deviceFamily: "iphone")
    }
    @Test func olderEqualNewerAndVersionTransitions() throws {
        #expect(try BetaReleaseManifest.target(from: payload(), installed: installed(build: 122), now: now)?.build == 124)
        #expect(try BetaReleaseManifest.target(from: payload(), installed: installed(build: 124), now: now) == nil)
        #expect(try BetaReleaseManifest.target(from: payload(), installed: installed(build: 125), now: now) == nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "1.2"), installed: installed(), now: now) != nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "1.10"), installed: installed(version: "1.9"), now: now) != nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "1.0"), installed: installed(), now: now) == nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "2.0", build: 1), installed: installed(), now: now) == nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "1.1.0"), installed: installed(), now: now) != nil)
        #expect(try BetaReleaseManifest.target(from: payload(version: "1..2"), installed: installed(), now: now) == nil)
        #expect(try BetaReleaseManifest.target(from: payload(), installed: installed(version: "unknown"), now: now) == nil)
    }
    @Test func privateExpiredStaleUnsupportedAndInvalidDataFailOpen() throws {
        let date = ISO8601DateFormatter()
        for data in [try payload(audience: "scott-only"), try payload(groups: ["a7c07355-b794-49b9-b36d-75c129c8d6bb"]),
                     try payload(expiry: date.string(from: now)), try payload(confirmed: date.string(from: now.addingTimeInterval(-86400))),
                     try payload(confirmed: date.string(from: now.addingTimeInterval(1))), try payload(expiry: "bad"),
                     try payload(minimum: "27.0"), try payload(groups: Array(BetaRelease.supportedGroups)+["unknown"])] {
            #expect(try BetaReleaseManifest.target(from: data, installed: installed(), now: now) == nil)
        }
        #expect(try BetaReleaseManifest.target(from: Data(repeating: 0, count: 16385), installed: installed(), now: now) == nil)
        #expect(throws: (any Error).self) { try BetaReleaseManifest.target(from: Data("{bad}".utf8), installed: installed(), now: now) }
        let disabled = BetaReleaseManifest(schemaVersion: 1, bundleID: "com.sfrancoe.HubBall", enabled: false, target: nil)
        #expect(try BetaReleaseManifest.target(from: JSONEncoder().encode(disabled), installed: installed(), now: now) == nil)
    }
    @Test func dismissalRelaunchNewTargetAndStoryOrdering() async throws {
        let suite = "beta-update-test-\(UUID().uuidString)"; let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = now, bytes = try payload(), future = now.addingTimeInterval(7 * 86400 + 1)
        let first = BetaUpdateStore(installed: installed(), defaults: defaults, clock: { time }, eligibility: { true }, fetch: { bytes })
        await first.check()
        #expect(first.offer(completedOnboarding: false, storyConsumed: true, busy: false) == nil)
        #expect(first.offer(completedOnboarding: true, storyConsumed: false, busy: false) == nil)
        #expect(first.offer(completedOnboarding: true, storyConsumed: true, busy: true) == nil)
        let offer = try #require(first.offer(completedOnboarding: true, storyConsumed: true, busy: false))
        first.later(offer)
        #expect(first.offer(completedOnboarding: true, storyConsumed: true, busy: false) == nil)
        let relaunched = BetaUpdateStore(installed: installed(), defaults: defaults, clock: { time }, eligibility: { true }, fetch: { bytes })
        await relaunched.check()
        #expect(relaunched.offer(completedOnboarding: true, storyConsumed: true, busy: false) == nil)
        let fresh = try payload(build: 125)
        let newRelease = BetaUpdateStore(installed: installed(), defaults: defaults, clock: { time }, eligibility: { true }, fetch: { fresh })
        await newRelease.check()
        #expect(newRelease.offer(completedOnboarding: true, storyConsumed: true, busy: false)?.build == 125)
        var expiredObject = try #require(JSONSerialization.jsonObject(with: bytes) as? [String:Any])
        var target = try #require(expiredObject["target"] as? [String:Any]);let date = ISO8601DateFormatter()
        target["confirmedAt"] = date.string(from: future);target["expiresAt"] = date.string(from: future.addingTimeInterval(86400));expiredObject["target"] = target
        let freshAfterSnooze = try JSONSerialization.data(withJSONObject: expiredObject)
        let after = BetaUpdateStore(installed: installed(), defaults: defaults, clock: { future }, eligibility: { true }, fetch: { freshAfterSnooze })
        await after.check()
        #expect(after.offer(completedOnboarding: true, storyConsumed: true, busy: false)?.build == 124)
    }
    @Test func offlineMalformedUnknownEligibilityAndNoStaleFallback() async throws {
        let time = now, fixture = BetaFixture(), data = try payload()
        await fixture.set(data)
        let store = BetaUpdateStore(installed: installed(), clock: { time }, eligibility: { true }, fetch: { try await fixture.load() })
        await store.check(); #expect(store.candidate != nil)
        await fixture.set(data, fail: true); await store.check(force: true); #expect(store.candidate == nil)
        await fixture.set(Data("{}".utf8)); await store.check(force: true); #expect(store.candidate == nil)
        let unknown = BetaUpdateStore(installed: installed(), clock: { time }, eligibility: { false }, fetch: { data })
        await unknown.check(); #expect(unknown.candidate == nil)
        #expect(BetaUpdateStore.helpURL.absoluteString == "https://testflight.apple.com/")
    }
    @Test func visibleTargetExpiresWithoutForegroundOrNetwork() async throws {
        let current = Date(), date = ISO8601DateFormatter()
        var object = try #require(JSONSerialization.jsonObject(with: payload()) as? [String:Any])
        var target = try #require(object["target"] as? [String:Any])
        target["confirmedAt"] = date.string(from: current)
        target["expiresAt"] = date.string(from: Date(timeIntervalSince1970: floor(current.timeIntervalSince1970) + 2))
        object["target"] = target
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let store = BetaUpdateStore(installed: installed(), eligibility: { true }, fetch: { bytes })
        await store.check(); #expect(store.candidate != nil)
        try await Task.sleep(for: .seconds(2.2))
        #expect(store.candidate == nil)
    }

    @Test func realHTTPManifestBypassesCaches() async throws {
        let root = try #require(ProcessInfo.processInfo.environment["HUB_HTTP_CACHE_FIXTURE_ORIGIN"])
        let url = try #require(URL(string: root + "/beta-fixture/releases/testflight-v1.json"))
        let current = Date(), api = APIClient(session: URLSession(configuration: .ephemeral))
        let store = BetaUpdateStore(installed: installed(build: 1), clock: { current }, eligibility: { true }, fetch: {
            try await api.data(.url(url), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        })
        await store.check(); #expect(store.candidate?.build == 9999)
    }
}
