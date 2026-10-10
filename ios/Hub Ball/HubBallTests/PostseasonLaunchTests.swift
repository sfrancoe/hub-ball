import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor struct PostseasonLaunchTests {
    private func store(enabled: Bool = true, delay: Bool = false) throws -> BetaUpdateStore {
        let now = Date(), dates = ISO8601DateFormatter()
        let target = BetaRelease(version: "1.1", build: 9999, audience: "all-supported-testers", available: true,
                                 confirmedAt: dates.string(from: now), expiresAt: dates.string(from: now.addingTimeInterval(3600)),
                                 minimumOS: "17.0", deviceFamilies: ["iphone", "ipad"], verifiedGroupIDs: Array(BetaRelease.supportedGroups))
        let bytes = try JSONEncoder().encode(BetaReleaseManifest(schemaVersion: 1, bundleID: "com.sfrancoe.HubBall", enabled: enabled, target: enabled ? target : nil))
        let defaults = UserDefaults(suiteName: "postseason-launch-test-" + UUID().uuidString)!
        return BetaUpdateStore(installed: InstalledBeta(version: "1.1", build: 124, os: "26.5", deviceFamily: "iphone"), defaults: defaults,
                               eligibility: { true }, fetch: {
            if delay {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { continuation.resume() }
                }
            }
            return bytes
        })
    }
    @Test func noticeBeforeStoryDismissOnceAndNoForegroundReplay() async throws {
        let updates = try store(), flow = PostseasonLaunchFlow()
        flow.begin(updates: updates)
        try await Task.sleep(for: .milliseconds(20))
        #expect(flow.phase == .notice && flow.target?.build == 9999)
        flow.didPresentStory(); #expect(flow.phase == .notice)
        flow.dismissNotice(updates: updates); #expect(flow.phase == .ready && flow.target == nil)
        flow.didPresentStory(); #expect(flow.phase == .story)
        flow.storyDismissed(); #expect(flow.phase == .finished)
        flow.setActive(false); flow.setActive(true); flow.begin(updates: updates)
        #expect(flow.phase == .finished)
    }
    @Test func disabledManifestAndUncooperativeDeadlineProceedWithoutLateNotice() async throws {
        let disabled = PostseasonLaunchFlow(), off = try store(enabled: false)
        disabled.begin(updates: off); try await Task.sleep(for: .milliseconds(20))
        #expect(disabled.phase == .ready)
        let slow = PostseasonLaunchFlow(), updates = try store(delay: true)
        slow.begin(updates: updates, timeout: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(30)); #expect(slow.phase == .ready)
        slow.didPresentStory()
        try await Task.sleep(for: .milliseconds(170))
        #expect(slow.phase == .story && slow.target == nil && updates.candidate == nil)
    }
    @Test func handoffWaitsForReturnInBothCompletionOrdersAndFailureWaitsForSheet() async throws {
        for completionFirst in [true, false] {
            let flow = PostseasonLaunchFlow(), updates = try store()
            flow.begin(updates: updates); try await Task.sleep(for: .milliseconds(20))
            flow.beginHandoff(updates: updates); #expect(flow.phase == .opening)
            if completionFirst { flow.handoffFinished(opened: true); #expect(flow.phase == .awaitingReturn) }
            flow.setActive(false)
            if !completionFirst { flow.setActive(true); flow.handoffFinished(opened: true) }
            else { #expect(flow.phase == .awaitingReturn); flow.setActive(true) }
            #expect(flow.phase == .ready)
        }
        let flow = PostseasonLaunchFlow(), updates = try store()
        flow.begin(updates: updates); try await Task.sleep(for: .milliseconds(20))
        flow.beginHandoff(updates: updates); flow.handoffFinished(opened: false)
        #expect(flow.phase == .instructions)
        flow.setActive(false); flow.setActive(true); #expect(flow.phase == .instructions)
        flow.instructionsDismissed(); #expect(flow.phase == .ready)
    }
    @Test func finalHoldPausesInBackgroundAndReplayResetsBothDurations() {
        for duration in [6.0, 15.0] {
            var hold = StoryCompletionHold()
            let first = hold.tick(now: 0, complete: true, duration: duration); #expect(!first)
            let before = hold.tick(now: duration - 1, complete: true, duration: duration); #expect(!before)
            hold.pause()
            let resumed = hold.tick(now: 100, complete: true, duration: duration); #expect(!resumed)
            let final = hold.tick(now: 101, complete: true, duration: duration); #expect(final)
            hold.reset(); let replayed = hold.tick(now: 200, complete: true, duration: duration); #expect(!replayed)
            let incomplete = hold.tick(now: 205, complete: false, duration: duration); #expect(!incomplete && hold.elapsed == 0)
        }
    }
}
