import XCTest

final class ClevelandStoryUITests: XCTestCase {
    private var app: XCUIApplication!
    private var root: String { ProcessInfo.processInfo.environment["HUB_UI_UPDATE_ROOT"]! }
    private var heading: XCUIElement { app.staticTexts["out-grid.heading"] }
    private var summary: XCUIElement { app.descendants(matching: .any).matching(identifier:"out-grid.summary").firstMatch }
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCTAssertFalse(root.isEmpty, "A real update fixture root is required")
        app = XCUIApplication(bundleIdentifier:"com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_STORY_CLEVELAND_LAUNCH":"1","HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data","HUB_STORY_ROOT":"http://127.0.0.1:1/data","HUB_STORY_CACHE_NAME":"cleveland-"+UUID().uuidString,"HUB_UPDATE_ROOT":root.replacingOccurrences(of:"/beta-fixture",with:"/beta-disabled-fixture"),"HUB_UPDATE_TEST_BETA":"1","HUB_UPDATE_TEST_BUILD":"125","HUB_UPDATE_TEST_DEFAULTS":"cleveland-"+UUID().uuidString,"HUB_TESTFLIGHT_HANDOFF":"failure"]
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func shot(_ name: String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
        let b=XCTAttachment(string:app.debugDescription);b.name=name+"-tree";b.lifetime = .keepAlways;add(b)
    }
    private func grid() {
        XCTAssertTrue(heading.waitForExistence(timeout:7));XCTAssertEqual(heading.label,"Wow!")
        XCTAssertEqual(app.staticTexts["out-grid.commentary"].label,"Cleveland set a major league record (regular OR postseason) for the number of strikeouts in a 9-inning game going back to 1900. They did this in the deciding Game 5 of the ALDS. Guardians move on after winning 2-0.")
        XCTAssertFalse(app.staticTexts["remote.title"].exists)
        XCTAssertFalse(app.buttons["trajectory.sources"].exists)
    }
    private func complete() {
        let e=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@","27 of 27 outs revealed"),object:summary)
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:14),.completed)
        XCTAssertTrue(summary.label.contains("21 OF 27"),summary.label)
    }
    private func landing() {
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["postseason.landing.title"].exists)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 { if element.isHittable { return };app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func wait(_ seconds: Double) {
        let e=XCTNSPredicateExpectation(predicate:NSPredicate(value:false),object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[e],timeout:seconds),.timedOut)
    }
    @MainActor func testAutomaticRevealReplayAndColdLaunch() {
        app.launch();grid();shot("cleveland-phone-start");complete();shot("cleveland-final-21-of-27")
        let replay=app.buttons["out-grid.replay"];reveal(replay);replay.tap();replay.tap()
        XCTAssertNotEqual(summary.value as? String,"27 of 27 outs revealed")
        complete();app.buttons["private-launch.dismiss"].tap();landing()
        XCUIDevice.shared.press(.home);app.activate();XCTAssertFalse(heading.exists)
        app.terminate();app.launch();grid();app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testNaturalCompletionAndManualStoriesPreserved() {
        app.launch();grid();complete()
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:9));landing()
        app.buttons["stories.open"].tap()
        let old=app.buttons["stories.private.separated-by-one"];reveal(old);old.tap()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:6));XCTAssertEqual(app.staticTexts["remote.title"].label,"Separated by One")
        app.navigationBars.buttons.element(boundBy:0).tap()
        let current=app.buttons["stories.private.almost-every-out-a-k"];reveal(current);current.tap();grid();complete();wait(7)
        XCTAssertTrue(heading.exists);XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["stories.close"].tap();landing()
    }
    @MainActor func testUpdateNoticeFirstDismissThenCleveland() {
        app.launchEnvironment["HUB_UPDATE_ROOT"]=root;app.launch()
        XCTAssertTrue(app.buttons["beta-update.update"].waitForExistence(timeout:6));XCTAssertFalse(heading.exists)
        XCTAssertEqual(app.buttons["beta-update.later"].label,"Dismiss");shot("cleveland-update-first")
        app.buttons["beta-update.later"].tap();grid();app.buttons["private-launch.dismiss"].tap();landing()
        app.terminate();app.launch();grid();XCTAssertFalse(app.buttons["beta-update.update"].exists)
        app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testUpdateFailureInstructionsBeforeStory() {
        app.launchEnvironment["HUB_UPDATE_ROOT"]=root;app.launch()
        XCTAssertTrue(app.buttons["beta-update.update"].waitForExistence(timeout:6));app.buttons["beta-update.update"].tap()
        XCTAssertTrue(app.staticTexts["TestFlight didn’t open"].waitForExistence(timeout:5));XCTAssertFalse(heading.exists)
        app.buttons["beta-update.done"].tap();grid();app.buttons["private-launch.dismiss"].tap();landing()
    }
    @MainActor func testUpdateSuccessWaitsForActualForegroundReturn() {
        app.launchEnvironment["HUB_UPDATE_ROOT"]=root;app.launchEnvironment["HUB_TESTFLIGHT_HANDOFF"]="success";app.launch()
        XCTAssertTrue(app.buttons["beta-update.update"].waitForExistence(timeout:6));app.buttons["beta-update.update"].tap();wait(1)
        XCTAssertFalse(heading.exists);XCTAssertFalse(app.staticTexts["TestFlight didn’t open"].exists)
        XCUIDevice.shared.press(.home);app.activate();grid();app.buttons["private-launch.dismiss"].tap();landing()
        XCUIDevice.shared.press(.home);app.activate();XCTAssertFalse(heading.exists)
    }
    @MainActor func testOfflineAndSlowUpdateCheckDoNotBlockStory() {
        for endpoint in ["http://127.0.0.1:1",root.replacingOccurrences(of:"/beta-fixture",with:"/beta-slow-fixture")] {
            app.launchEnvironment["HUB_UPDATE_ROOT"]=endpoint;app.launch();grid();wait(3)
            XCTAssertFalse(app.buttons["beta-update.update"].exists)
            app.buttons["private-launch.dismiss"].tap();landing();app.terminate()
        }
    }
    @MainActor func testBackgroundPausesAnimationAndFinalHold() {
        app.launch();grid();XCUIDevice.shared.press(.home);wait(3);app.activate();grid();complete()
        XCUIDevice.shared.press(.home);wait(7);app.activate();XCTAssertTrue(heading.exists)
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:9));landing()
    }
    @MainActor func testLargestTextReduceMotionReplayAndReadingHold() {
        app.launchArguments[5]="UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1";app.launch();grid();complete();shot("cleveland-largest-final")
        XCTAssertGreaterThan(app.staticTexts["out-grid.commentary"].frame.height,200)
        XCTAssertTrue(app.buttons["private-launch.dismiss"].isHittable)
        let replay=app.buttons["out-grid.replay"];reveal(replay);XCTAssertGreaterThanOrEqual(replay.frame.height,44);replay.tap();complete();wait(7)
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(app.buttons["private-launch.dismiss"].waitForNonExistence(timeout:19));landing()
    }
}
