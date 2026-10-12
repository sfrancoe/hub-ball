import XCTest
import Foundation

final class HookCardUITests: XCTestCase {
    private var app: XCUIApplication!
    private var root: String { ProcessInfo.processInfo.environment["HUB_UI_FEATURED_ROOT"] ?? "" }
    private var updateRoot: String { ProcessInfo.processInfo.environment["HUB_UI_UPDATE_ROOT"] ?? "" }
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data","HUB_STORY_ROOT":"http://127.0.0.1:1/data",
            "HUB_FEATURED_CACHE_NAME":"hook-"+UUID().uuidString,"HUB_FEATURED_ACK_DEFAULTS":"hook-"+UUID().uuidString,
            "HUB_UPDATE_ROOT":updateRoot.replacingOccurrences(of:"/beta-fixture",with:"/beta-disabled-fixture"),
            "HUB_UPDATE_TEST_BETA":"1","HUB_UPDATE_TEST_BUILD":"128","HUB_UPDATE_TEST_DEFAULTS":"hook-"+UUID().uuidString,"HUB_TESTFLIGHT_HANDOFF":"failure"]
        app.launchEnvironment["HUB_FEATURED_ROOT"] = root
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func mode(_ value: String) async throws {
        let url=URL(string:root.replacingOccurrences(of:"/featured-fixture",with:"/featured-fixture-control")+"?mode="+value)!
        let (_,response)=try await URLSession.shared.data(from:url);XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
    }
    private func card() {
        XCTAssertTrue(app.staticTexts["featured.hook"].waitForExistence(timeout:7))
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"trajectory.chart").firstMatch.exists)
        XCTAssertEqual(app.staticTexts["featured.hook-summary"].label,"In his entire Major League career he had pitched just eight innings up until this year. In 2026 he pitched 172⅔.")
    }
    private func landing() {
        XCTAssertTrue(app.staticTexts["featured.hook"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["postseason.landing.title"].waitForExistence(timeout:5))
    }
    private func play() {
        let button=app.buttons["featured.play"]
        for _ in 0..<8 { if button.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable);button.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"trajectory.chart").firstMatch.waitForExistence(timeout:5))
    }
    private func shot(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a);let b=XCTAttachment(string:app.debugDescription);b.name=name+"-tree";b.lifetime = .keepAlways;add(b) }
    @MainActor func testDismissPersistsAcrossRelaunchAndSameIDRevision() async throws {
        try await mode("screening");app.launch();card();shot("griffin-hook-only")
        app.buttons["featured.dismiss"].tap();landing();app.terminate();app.launch();landing()
        app.terminate();try await mode("screening-revised");app.launch();landing()
        XCUIDevice.shared.press(.home);app.activate();landing()
    }
    @MainActor func testPlayRecordedBeforeInterruptedPlaybackAndAToBToA() async throws {
        try await mode("screening");app.launch();card();play();shot("griffin-chart-building")
        app.terminate();app.launch();landing();app.terminate()
        try await mode("screening-b");app.launch()
        XCTAssertTrue(app.staticTexts["featured.hook"].waitForExistence(timeout:7))
        XCTAssertEqual(app.staticTexts["featured.hook"].label,"A second story for the next opening.")
        app.buttons["featured.dismiss"].tap();landing();app.terminate()
        try await mode("screening");app.launch();landing()
    }
    @MainActor func testSwipeDismissalPersists() async throws {
        try await mode("screening");app.launch();card()
        app.swipeDown(velocity:.fast);landing();app.terminate();app.launch();landing()
    }
    @MainActor func testUpdateNoticePrecedesCardAndFailedHandoff() async throws {
        try await mode("screening");app.launchEnvironment["HUB_UPDATE_ROOT"]=updateRoot;app.launch()
        XCTAssertTrue(app.buttons["beta-update.update"].waitForExistence(timeout:7))
        XCTAssertFalse(app.staticTexts["featured.hook"].exists)
        app.buttons["beta-update.update"].tap()
        XCTAssertTrue(app.buttons["beta-update.done"].waitForExistence(timeout:5))
        app.buttons["beta-update.done"].tap();card();app.buttons["featured.dismiss"].tap();landing()
    }
    @MainActor func testReducedMotionExactThirdsReplayAndCompletion() async throws {
        try await mode("screening");app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1";app.launch();card();play()
        let chart=app.descendants(matching:.any).matching(identifier:"trajectory.chart").firstMatch
        XCTAssertTrue(chart.value.debugDescription.contains("172⅔"));XCTAssertTrue(chart.value.debugDescription.contains("JAPAN"))
        XCTAssertFalse(app.staticTexts["trajectory.conclusion"].exists)
        shot("griffin-exact-thirds-japan-final");app.buttons["trajectory.replay"].tap()
        XCUIDevice.shared.press(.home);try await Task.sleep(nanoseconds:7_000_000_000);app.activate()
        XCTAssertTrue(chart.exists);XCTAssertTrue(app.buttons["featured.close"].waitForNonExistence(timeout:12));landing()
    }
    @MainActor func testLargestTextCardAndChartRemainReadable() async throws {
        try await mode("screening");app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1"
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch();card();shot("griffin-largest-hook");play()
        let replay=app.buttons["trajectory.replay"]
        for _ in 0..<10 { if replay.isHittable { break };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(replay.isHittable);shot("griffin-largest-chart")
        let plot = app.scrollViews["trajectory.plot-scroll"]
        if plot.exists { plot.swipeLeft(); shot("griffin-largest-right-endpoint") }
        replay.tap()
        app.buttons["featured.close"].tap();landing()
    }
    @MainActor func testCachedUnansweredCardOfflineAndExpiredSkip() async throws {
        try await mode("screening");app.launch();card();app.terminate()
        try await mode("offline");app.launch();card();app.terminate()
        try await mode("screening-expired");app.launch();landing()
    }
    @MainActor func testPrivateBundleManualReplayFromStories() async throws {
        app.launchEnvironment.removeValue(forKey:"HUB_FEATURED_ROOT");app.launch();card();play()
        app.buttons["featured.close"].tap();landing();app.buttons["stories.open"].tap()
        let link=app.buttons["stories.preview.griffin-eight-innings-alcs"]
        for _ in 0..<8 { if link.isHittable { break };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(link.isHittable);link.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"trajectory.chart").firstMatch.waitForExistence(timeout:5));shot("griffin-private-manual-replay")
        XCTAssertFalse(app.buttons["featured.close"].exists)
    }
}
