import XCTest

final class BetaUpdateUITests: XCTestCase {
    private var app: XCUIApplication!
    private var root = ""
    override func setUpWithError() throws {
        continueAfterFailure = false
        root = try XCTUnwrap(ProcessInfo.processInfo.environment["HUB_UI_UPDATE_ROOT"])
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data","HUB_STORY_ROOT":"http://127.0.0.1:1/data",
                                 "HUB_TESTFLIGHT_HANDOFF":"failure","HUB_UPDATE_ROOT":root,"HUB_UPDATE_TEST_BETA":"1","HUB_UPDATE_TEST_BUILD":"124","HUB_UPDATE_TEST_DEFAULTS":"launch-ui-"+UUID().uuidString]
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        let tree = XCTAttachment(string:app.debugDescription);tree.name=name+"-tree";tree.lifetime = .keepAlways;add(tree)
    }
    private func launchNotice() {
        app.launch()
        XCTAssertTrue(app.buttons["beta-update.update"].waitForExistence(timeout:6))
        XCTAssertTrue(app.staticTexts["New version of Hub Ball"].exists)
        XCTAssertTrue(app.staticTexts["postseason.landing.title"].exists)
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        XCTAssertEqual(app.buttons["beta-update.update"].label,"Open TestFlight to update")
        XCTAssertEqual(app.buttons["beta-update.later"].label,"Dismiss")
    }
    private func story() {
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:6))
        XCTAssertEqual(app.staticTexts["remote.title"].label,"Separated by One")
        XCTAssertFalse(app.buttons["beta-update.update"].exists)
    }
    private func landing() {
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["postseason.landing.title"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        XCTAssertFalse(app.buttons["beta-update.update"].exists)
    }
    private func disabled() { app.launchEnvironment["HUB_UPDATE_ROOT"] = root.replacingOccurrences(of:"/beta-fixture",with:"/beta-disabled-fixture") }
    private func complete() {
        let e = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Chart complete"),object:app.staticTexts["trajectory.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:14),.completed)
        let value = app.otherElements["trajectory.chart"].value as? String ?? ""
        XCTAssertTrue(value.contains("58") && value.contains("57"),value)
    }
    private func remainsStory(_ seconds: Double) {
        let e = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.staticTexts["remote.title"]);e.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:seconds),.completed)
    }
    @MainActor func testNoticeFirstDismissStoryThenPostseasonAndColdLaunchSnooze() {
        launchNotice();capture("launch-notice-first")
        app.buttons["beta-update.later"].tap();story()
        app.buttons["private-launch.dismiss"].tap();landing();capture("launch-postseason-after-dismiss")
        XCUIDevice.shared.press(.home);app.activate();landing()
        app.terminate();app.launch();story();app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testDisabledAndOfflineProceedPromptly() {
        for offline in [false,true] {
            if offline { app.launchEnvironment["HUB_UPDATE_ROOT"] = "http://127.0.0.1:1" } else { disabled() }
            app.launch();story();app.buttons["private-launch.dismiss"].tap();landing();app.terminate()
        }
    }
    @MainActor func testSlowCheckDeadlineDoesNotOfferLateNotice() {
        app.launchEnvironment["HUB_UPDATE_ROOT"] = root.replacingOccurrences(of:"/beta-fixture",with:"/beta-slow-fixture")
        app.launch();story();remainsStory(3)
        app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testNaturalCompletionReplayAndManualStoryDoesNotRedirect() {
        disabled();app.launch();story();complete();capture("launch-final-payoff")
        app.buttons["trajectory.replay"].tap();XCTAssertEqual(app.staticTexts["trajectory.status"].label,"Chart building")
        complete()
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:9));landing()
        app.buttons["stories.open"].tap()
        let card = app.buttons["stories.private.separated-by-one"]
        for _ in 0..<12 { if card.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.isHittable);card.tap()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:5));complete();remainsStory(7)
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["stories.close"].tap();landing()
    }
    @MainActor func testBackgroundFreezesFinalHold() {
        disabled();app.launch();story();complete()
        XCUIDevice.shared.press(.home)
        let e = XCTNSPredicateExpectation(predicate:NSPredicate(value:false),object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:7),.timedOut)
        app.activate();XCTAssertTrue(app.staticTexts["remote.title"].exists)
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:9));landing()
    }
    @MainActor func testSuccessfulUpdateWaitsForForegroundThenStoryOnce() {
        app.launchEnvironment["HUB_TESTFLIGHT_HANDOFF"] = "success"
        launchNotice();app.buttons["beta-update.update"].tap()
        XCTAssertFalse(app.staticTexts["remote.title"].exists)
        XCTAssertFalse(app.staticTexts["beta-update.instructions"].exists)
        XCUIDevice.shared.press(.home);app.activate();story()
        app.buttons["private-launch.dismiss"].tap();landing()
        XCUIDevice.shared.press(.home);app.activate();landing()
    }
    @MainActor func testFailedUpdateInstructionsDismissBeforeStory() {
        launchNotice();app.buttons["beta-update.update"].tap()
        XCTAssertTrue(app.staticTexts["TestFlight didn’t open"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["remote.title"].exists);capture("launch-handoff-failure")
        app.buttons["beta-update.done"].tap();story();app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testRealUniversalLinkFailureStillStartsStoryAfterInstructions() {
        app.launchEnvironment.removeValue(forKey:"HUB_TESTFLIGHT_HANDOFF")
        launchNotice();app.buttons["beta-update.update"].tap()
        XCTAssertTrue(app.staticTexts["TestFlight didn’t open"].waitForExistence(timeout:5))
        app.buttons["beta-update.done"].tap();story();app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testLargestTextReducedMotionHoldSourcesReplayAndPostseason() {
        app.launchArguments[3] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        launchNotice();capture("launch-largest-notice")
        for id in ["beta-update.update","beta-update.later"] { XCTAssertTrue(app.buttons[id].isHittable);XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height,44) }
        app.buttons["beta-update.later"].tap();story();complete();capture("launch-largest-final")
        remainsStory(7)
        app.buttons["trajectory.replay"].tap();complete()
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:19));landing()
    }
    @MainActor func testIntentionalTeamNavigationAndManualStoryKeepsTeamDestination() {
        disabled();app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        app.launch();story();app.buttons["private-launch.dismiss"].tap();landing()
        app.buttons["Switch team"].tap()
        let boston = app.buttons["Boston Red Sox"].firstMatch
        XCTAssertTrue(boston.waitForExistence(timeout:5));boston.tap()
        XCTAssertFalse(app.staticTexts["postseason.landing.title"].exists)
        XCTAssertTrue(app.buttons["stories.open"].isHittable)
        app.buttons["stories.open"].tap()
        let card = app.buttons["stories.private.separated-by-one"]
        for _ in 0..<12 { if card.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.isHittable);card.tap()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:5));complete();remainsStory(7)
        let data = app.buttons["trajectory.data"]
        for _ in 0..<8 { if data.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(data.isHittable);data.tap()
        XCTAssertTrue(app.buttons["trajectory.data.close"].waitForExistence(timeout:5));app.buttons["trajectory.data.close"].tap()
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["stories.close"].tap()
        XCTAssertFalse(app.staticTexts["postseason.landing.title"].exists)
        app.buttons["playoffs.open"].tap();landing()
    }

}
