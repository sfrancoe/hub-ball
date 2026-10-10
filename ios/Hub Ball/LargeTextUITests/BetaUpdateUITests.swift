import XCTest

final class BetaUpdateUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["HUB_UI_UPDATE_ROOT"])
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data","HUB_STORY_ROOT":"http://127.0.0.1:1/data",
                                 "HUB_TESTFLIGHT_HANDOFF":"failure","HUB_UPDATE_ROOT":root,"HUB_UPDATE_TEST_BETA":"1","HUB_UPDATE_TEST_BUILD":"123","HUB_UPDATE_TEST_DEFAULTS":"beta-ui-"+UUID().uuidString]
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func launchStory() {
        app.launch()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["remote.title"].label,"Separated by One")
        XCTAssertFalse(app.buttons["beta-update.update"].exists)
        XCTAssertTrue(app.buttons["private-launch.dismiss"].isHittable)
    }
    private func dismissStory() { app.buttons["private-launch.dismiss"].tap() }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name=name;image.lifetime = .keepAlways;add(image)
        let tree = XCTAttachment(string:app.debugDescription);tree.name=name+"-tree";tree.lifetime = .keepAlways;add(tree)
    }
    @MainActor func testStoryFirstUpdateInstructionsAndRelaunchSuppression() {
        launchStory();dismissStory()
        let update = app.buttons["beta-update.update"]
        XCTAssertTrue(update.waitForExistence(timeout:10));XCTAssertTrue(update.isHittable)
        XCTAssertEqual(update.label,"Open TestFlight to update")
        XCTAssertEqual(app.buttons["beta-update.later"].label,"Dismiss")
        XCTAssertTrue(app.staticTexts["New version of Hub Ball"].exists);capture("beta-notice")
        app.buttons["stories.open"].tap()
        XCTAssertTrue(app.buttons["stories.close"].waitForExistence(timeout:5));XCTAssertFalse(update.exists)
        app.buttons["stories.close"].tap();XCTAssertTrue(update.waitForExistence(timeout:5))
        update.tap()
        XCTAssertTrue(app.staticTexts["beta-update.instructions"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["beta-update.done"].isHittable);capture("beta-instructions")
        app.buttons["beta-update.done"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
        XCTAssertFalse(update.exists)
        XCUIDevice.shared.press(.home);app.activate();XCTAssertFalse(update.exists)
        app.terminate();launchStory();dismissStory()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5));XCTAssertFalse(update.exists)
    }
    @MainActor func testLaterPersistsAndStoryCanReopen() {
        launchStory();dismissStory()
        let later = app.buttons["beta-update.later"]
        XCTAssertTrue(later.waitForExistence(timeout:10));XCTAssertGreaterThanOrEqual(later.frame.height,44);later.tap()
        XCTAssertFalse(later.exists)
        app.buttons["stories.open"].tap()
        XCTAssertTrue(app.buttons["stories.close"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["beta-update.update"].exists)
        app.buttons["stories.close"].tap()
        app.terminate();launchStory();dismissStory()
        XCTAssertFalse(later.exists)
    }
    @MainActor func testLargestTextControlsAndInstructions() {
        app.launchArguments[5] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        launchStory();dismissStory()
        let update = app.buttons["beta-update.update"], later = app.buttons["beta-update.later"]
        XCTAssertTrue(update.waitForExistence(timeout:10));XCTAssertTrue(update.isHittable);XCTAssertTrue(later.isHittable)
        XCTAssertGreaterThanOrEqual(update.frame.height,44);XCTAssertGreaterThanOrEqual(later.frame.height,44)
        XCTAssertLessThanOrEqual(update.frame.maxX,app.frame.maxX);capture("beta-largest-notice")
        update.tap();XCTAssertTrue(app.buttons["beta-update.done"].waitForExistence(timeout:5));capture("beta-largest-instructions")
        let help = app.descendants(matching:.any).matching(identifier:"beta-update.help").firstMatch
        for _ in 0..<15 { if help.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(help.isHittable);capture("beta-largest-help")
        app.buttons["beta-update.done"].tap();XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
    }
    @MainActor func testOfflineHasNoNoticeAndStoryStillAutoplays() {
        app.launchEnvironment["HUB_UPDATE_ROOT"] = "http://127.0.0.1:1"
        launchStory();dismissStory()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["beta-update.update"].exists)
    }
    @MainActor func testSuccessfulHandoffDoesNotPresentFailureInstructions() {
        app.launchEnvironment["HUB_TESTFLIGHT_HANDOFF"] = "success"
        launchStory();dismissStory()
        let update = app.buttons["beta-update.update"]
        XCTAssertTrue(update.waitForExistence(timeout:10));update.tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
        XCTAssertFalse(update.exists)
        XCTAssertFalse(app.staticTexts["beta-update.instructions"].exists)
    }

    @MainActor func testRealUniversalLinkAttemptFallsBackWhenTestFlightIsAbsent() {
        app.launchEnvironment.removeValue(forKey: "HUB_TESTFLIGHT_HANDOFF")
        launchStory();dismissStory()
        let update = app.buttons["beta-update.update"]
        XCTAssertTrue(update.waitForExistence(timeout:10));update.tap()
        XCTAssertTrue(app.staticTexts["TestFlight didn’t open"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["beta-update.instructions"].exists)
        XCTAssertTrue(app.buttons["beta-update.done"].isHittable)
    }

}
