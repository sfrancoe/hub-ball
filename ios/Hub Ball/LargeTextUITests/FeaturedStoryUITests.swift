import XCTest
import Foundation
import Darwin

final class FeaturedStoryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var root: String { ProcessInfo.processInfo.environment["HUB_UI_FEATURED_ROOT"] ?? "" }
    private var updateRoot: String { ProcessInfo.processInfo.environment["HUB_UI_UPDATE_ROOT"] ?? "" }
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data","HUB_STORY_ROOT":"http://127.0.0.1:1/data",
            "HUB_FEATURED_CACHE_NAME":"featured-"+UUID().uuidString,"HUB_UPDATE_ROOT":updateRoot.replacingOccurrences(of:"/beta-fixture",with:"/beta-disabled-fixture"),
            "HUB_UPDATE_TEST_BETA":"1","HUB_UPDATE_TEST_BUILD":"127","HUB_UPDATE_TEST_DEFAULTS":"featured-"+UUID().uuidString,"HUB_TESTFLIGHT_HANDOFF":"failure"]
        if !root.isEmpty { app.launchEnvironment["HUB_FEATURED_ROOT"] = root }
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func mode(_ value: String) async throws {
        XCTAssertFalse(root.isEmpty)
        let url = URL(string:root.replacingOccurrences(of:"/featured-fixture",with:"/featured-fixture-control")+"?mode="+value)!
        let (_,response) = try await URLSession.shared.data(from:url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
    }
    private func grid() {
        XCTAssertTrue(app.staticTexts["out-grid.heading"].waitForExistence(timeout:7))
        XCTAssertEqual(app.staticTexts["out-grid.heading"].label,"Wow!")
        XCTAssertEqual(app.staticTexts["out-grid.commentary"].label,"Cleveland set a major league record (regular OR postseason) for the number of strikeouts in a 9-inning game going back to 1900. They did this in the deciding Game 5 of the ALDS. Guardians move on after winning 2-0.")
    }
    private func dismissGrid() { app.buttons["private-launch.dismiss"].tap(); landing() }
    private func landing() {
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["postseason.landing.title"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["out-grid.heading"].exists)
    }
    private func shot(_ name: String) {
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        let tree=XCTAttachment(string:app.debugDescription);tree.name=name+"-tree";tree.lifetime = .keepAlways;add(tree)
    }
    private func wait(_ seconds: Double) async throws { try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)) }
    @MainActor func testRemoteGridNoticeFirstDismissAndForegroundDoesNotReopen() async throws {
        try await mode("good");app.launchEnvironment["HUB_UPDATE_ROOT"]=updateRoot;app.launch()
        XCTAssertTrue(app.buttons["beta-update.later"].waitForExistence(timeout:6))
        XCTAssertFalse(app.staticTexts["out-grid.heading"].exists);shot("remote-notice-first")
        app.buttons["beta-update.later"].tap();grid();shot("remote-cleveland-approved")
        dismissGrid();XCUIDevice.shared.press(.home);app.activate();landing()
        app.terminate();app.launch();grid();dismissGrid()
    }
    @MainActor func testOfflineAndBadHashKeepVerifiedCacheThenDisabledRevokes() async throws {
        try await mode("good");app.launch();grid();dismissGrid();app.terminate()
        for value in ["offline","bad-hash"] {
            try await mode(value);app.launch();grid();shot("remote-cache-"+value);dismissGrid();app.terminate()
        }
        try await mode("disabled");app.launch();try await wait(3);landing();shot("remote-disabled-postseason");app.terminate()
        try await mode("offline");app.launch();try await wait(3);landing()
    }
    @MainActor func testEmptyExpiredUnsupportedAndLateFetchSkipSafely() async throws {
        for value in ["offline","expired","unsupported","bad-hash","slow"] {
            app.launchEnvironment["HUB_FEATURED_CACHE_NAME"]="empty-"+UUID().uuidString
            try await mode(value);app.launch();try await wait(4);landing();shot("remote-skip-"+value)
            XCUIDevice.shared.press(.home);app.activate();landing();app.terminate()
        }
    }
    @MainActor func testDifferentRendererOnColdRelaunch() async throws {
        try await mode("good");app.launch();grid();dismissGrid();app.terminate()
        try await mode("trajectory");app.launch()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:7))
        XCTAssertEqual(app.staticTexts["remote.title"].label,"A Whole Season of Wins. By June.")
        XCTAssertFalse(app.staticTexts["out-grid.heading"].exists);shot("remote-trajectory")
        app.buttons["featured.close"].tap();landing()
    }
    @MainActor func testRemoteReducedMotionReplayAndAutomaticCompletion() async throws {
        try await mode("good");app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1";app.launch();grid()
        let replay=app.buttons["out-grid.replay"]
        for _ in 0..<8 { if replay.isHittable { break };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(replay.isHittable);shot("remote-grid-final");replay.tap();grid()
        XCUIDevice.shared.press(.home);try await wait(7);app.activate();grid()
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:12));landing()
        XCUIDevice.shared.press(.home);app.activate();landing()
    }
    @MainActor func testRemoteLargestTextReadableReplayAndDismiss() async throws {
        try await mode("good");app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1"
        app.launchArguments=["-hubCompletedTeamOnboarding","YES","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();grid();shot("remote-largest-heading-copy")
        let replay=app.buttons["out-grid.replay"]
        for _ in 0..<12 { if replay.isHittable { break };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(replay.isHittable);shot("remote-largest-grid-footer");replay.tap()
        app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testLargestTextCopyAtTopAndGridHorizontalScroll() async throws {
        try await mode("good");app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1"
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"]="9.6"
        app.launchArguments=["-hubCompletedTeamOnboarding","YES","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();grid()
        XCTAssertTrue(app.staticTexts["out-grid.heading"].isHittable)
        shot("remote-largest-copy-top")
        let replay=app.buttons["out-grid.replay"]
        for _ in 0..<12 { if replay.isHittable { break };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        let panels=app.descendants(matching:.any).matching(identifier:"out-grid.panels").firstMatch
        if panels.exists { panels.swipeLeft() }
        shot("remote-largest-scrollable-final-grid")
        app.buttons["private-launch.dismiss"].tap();landing()
    }
    private func liveRevision() async throws -> String {
        var request=URLRequest(url:URL(string:"https://api.autumnlane.io/api/data/stories/featured-v1.json")!);request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData;request.timeoutInterval=5
        let (bytes,response)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        return (try JSONSerialization.jsonObject(with:bytes) as? [String:Any])?["revision"] as? String ?? ""
    }
    private func awaitRevision(_ expected: String) async throws {
        for _ in 0..<600 { if try await liveRevision()==expected { return };try await wait(1) }
        throw NSError(domain:"FeaturedLiveProof",code:1,userInfo:[NSLocalizedDescriptionKey:"Live pointer never changed to "+expected])
    }
    @MainActor func testLivePublishedSwapWithoutReinstall() async throws {
        app.launchEnvironment.removeValue(forKey:"HUB_FEATURED_ROOT")
        let initial = try await liveRevision()
        XCTAssertEqual(initial,"scott-preview-cleveland-october11")
        app.launch();grid();shot("live-installed-127-story-a")
        // Keep this exact installed app while the human-authorized publisher changes only public JSON.
        app.terminate();print("LIVE_SWAP_READY_FOR_B");fflush(nil)
        try await awaitRevision("scott-preview-existing-trajectory")
        app.launch()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:7))
        XCTAssertEqual(app.staticTexts["remote.title"].label,"A Whole Season of Wins. By June.")
        XCTAssertFalse(app.staticTexts["out-grid.heading"].exists);shot("live-same-installed-127-story-b")
        app.buttons["featured.close"].tap();landing();app.terminate();print("LIVE_SWAP_B_SEEN_RESTORE_A");fflush(nil)
        try await awaitRevision("scott-preview-cleveland-october11")
        app.launch();grid();shot("live-same-installed-127-restored-a");dismissGrid()
        print("LIVE_SWAP_A_B_A_PASSED_NO_INSTALL_OR_REBUILD");fflush(nil)
    }
}
