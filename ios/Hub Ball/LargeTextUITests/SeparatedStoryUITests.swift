import XCTest

final class SeparatedStoryUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_STORY_SEPARATED_LAUNCH":"1","HUB_STORY_ROOT":"http://127.0.0.1:1/data","HUB_STORY_CACHE_NAME":"separated-"+UUID().uuidString.lowercased(),"HUB_API_ROOT":"http://127.0.0.1:1","HUB_DATA_ROOT":"http://127.0.0.1:1/data"]
        app.launchArguments = ["-hubCompletedTeamOnboarding","YES","-hubSelectedTeam","rays","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
    }
    override func tearDownWithError() throws { app.terminate() }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<25 {
            let identity = element.identifier.isEmpty ? element.label : element.identifier
            let scroll = app.scrollViews.containing(element.elementType,identifier:identity).firstMatch
            let owner = scroll.exists ? scroll : app!
            let bounds = owner.frame.intersection(app.frame)
            if element.exists && (element.isHittable || element.elementType == .other) && element.frame.midY > bounds.minY+20 && element.frame.midY < bounds.maxY-25 { return }
            let down = element.exists && element.frame.midY < bounds.minY+20
            owner.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:down ? 0.25:0.75)).press(forDuration:0.05,thenDragTo:owner.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:down ? 0.75:0.25)),withVelocity:.slow,thenHoldForDuration:0.2)
        }
        XCTFail("Cannot reveal \(element.identifier)")
    }
    private func launch() {
        app.launch()
        XCTAssertTrue(app.staticTexts["remote.title"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["remote.title"].label,"Separated by One")
        XCTAssertTrue(app.buttons["private-launch.dismiss"].exists)
        XCTAssertFalse(app.buttons["featured.watch"].exists)
    }
    private func complete() {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","Chart complete"),object:app.staticTexts["trajectory.status"])
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:15),.completed)
    }
    private func shot(_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
        let b=XCTAttachment(string:app.debugDescription);b.name=name+"-tree";b.lifetime = .keepAlways;add(b)
    }
    @MainActor func testAutoplayReplayBackgroundAndOfflineColdLaunch() {
        launch()
        XCTAssertEqual(app.staticTexts["trajectory.status"].label,"Chart building")
        let replay=app.buttons["trajectory.replay"];reveal(replay);replay.tap();replay.tap()
        XCUIDevice.shared.press(.home);app.activate();complete()
        XCTAssertEqual(app.staticTexts["trajectory.emphasis"].label,"Tonight: one game to advance.")
        reveal(app.otherElements["trajectory.chart"]);shot("separated-finished")
        reveal(replay);replay.tap();complete()
        app.buttons["private-launch.dismiss"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        app.terminate();launch();complete()
    }
    @MainActor func testDismissEarlyNavigateReopenAndRefresh() {
        launch();app.buttons["private-launch.dismiss"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
        app.buttons["stories.open"].tap()
        let refresh=app.buttons["stories.refresh"];reveal(refresh);refresh.tap()
        XCTAssertTrue(app.staticTexts["stories.offline"].waitForExistence(timeout:10))
        let card=app.buttons["stories.private.separated-by-one"];reveal(card);card.tap();complete()
        XCTAssertEqual(app.staticTexts["remote.title"].label,"Separated by One")
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["stories.close"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["private-launch.dismiss"].exists)
    }
    @MainActor func testLargestTextReducedMotionSourcesDataAndDismiss() {
        // Static snapshot/source exploration; real completion timing is covered by launch-flow UI tests.
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = "10"
        app.launchArguments[5]="UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"]="1"
        launch();complete();reveal(app.otherElements["trajectory.chart"]);shot("separated-largest")
        let chart=app.otherElements["trajectory.chart"]
        XCTAssertGreaterThanOrEqual(chart.frame.minX,0);XCTAssertLessThanOrEqual(chart.frame.maxX,app.frame.maxX)
        let replay=app.buttons["trajectory.replay"];reveal(replay);replay.tap();complete()
        XCTAssertFalse(app.buttons["trajectory.pause"].exists)
        let data=app.buttons["trajectory.data"];reveal(data);data.tap()
        XCTAssertTrue(app.navigationBars["Explore the data"].waitForExistence(timeout:5));app.buttons["trajectory.data.close"].tap()
        let sources=app.buttons["trajectory.sources"];reveal(sources);sources.tap()
        XCTAssertTrue(app.navigationBars["Sources & methodology"].waitForExistence(timeout:5));app.buttons["trajectory.sources.close"].tap()
        app.buttons["private-launch.dismiss"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout:5))
    }
    @MainActor func testFinalDirectLabelsLayout() {
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = "10"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        launch();complete();reveal(app.otherElements["trajectory.chart"]);shot("separated-final-direct-labels")
        XCTAssertEqual(app.staticTexts["trajectory.emphasis"].label,"Tonight: one game to advance.")
    }

    @MainActor func testWholeCountsAtIntermediateFramesAndExactEnd() {
        let moments: [Double] = [0, 0.25, 1.25, 2.5, 4.75, 6.2, 8.8, 9.95, 10]
        for moment in moments {
            app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = String(moment)
            launch()
            let chart = app.otherElements["trajectory.chart"]
            XCTAssertTrue(chart.exists)
            let value = chart.value as? String ?? ""
            XCTAssertFalse(value.isEmpty)
            XCTAssertNil(value.range(of: "[0-9]+[.,][0-9]+", options: .regularExpression))
            let counters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "trajectory.series."))
            XCTAssertEqual(counters.count, 2)
            for index in 0..<counters.count {
                XCTAssertNil(counters.element(boundBy:index).label.range(of: "[0-9]+[.,][0-9]+", options: .regularExpression))
            }
            if moment == 4.75 || moment == 10 { shot("separated-integer-frame-\(moment)") }
            if moment == 10 {
                let spoken = chart.value as? String ?? ""
                XCTAssertTrue(spoken.contains("58") && spoken.contains("57"), spoken)
            }
            app.terminate()
        }
    }

}
