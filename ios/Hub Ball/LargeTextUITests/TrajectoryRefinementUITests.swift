import XCTest

final class TrajectoryRefinementUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        let origin = try XCTUnwrap(ProcessInfo.processInfo.environment["HUB_UI_STORY_ROOT"])
        XCTAssertTrue(origin.hasPrefix("http://127.0.0.1:"))
        app.launchEnvironment = ["HUB_STORY_ROOT": origin + "/data", "HUB_STORY_CACHE_NAME": "refinement-" + UUID().uuidString.lowercased(),
                                 "HUB_API_ROOT": "http://127.0.0.1:1", "HUB_DATA_ROOT": "http://127.0.0.1:1/data"]
        app.launchArguments = ["-hubCompletedTeamOnboarding", "YES", "-hubSelectedTeam", "rays", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["HUB_STORY_LEGACY_LAUNCH"] = "1"
    }
    override func tearDownWithError() throws { app.terminate() }
    private func shot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<25 {
            let identity = element.identifier.isEmpty ? element.label : element.identifier
            let scroll = app.scrollViews.containing(element.elementType, identifier: identity).firstMatch
            let owner = scroll.exists ? scroll : app!
            let bounds = owner.frame.intersection(app.frame)
            if element.exists && (element.isHittable || element.elementType == .other) && element.frame.midY > bounds.minY + 20 && element.frame.midY < bounds.maxY - 25 { return }
            let down = element.exists && element.frame.midY < bounds.minY + 20
            let from = owner.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: down ? 0.25 : 0.75))
            let to = owner.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: down ? 0.75 : 0.25))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not reveal \(element.identifier)")
    }
    private func watch() {
        let watch = app.buttons["featured.watch"]
        XCTAssertTrue(watch.waitForExistence(timeout: 10)); reveal(watch); watch.tap()
        XCTAssertTrue(app.otherElements["trajectory.chart"].waitForExistence(timeout: 10))
    }
    private func complete() {
        let predicate = NSPredicate(format: "label == %@", "Chart complete")
        let wait = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["trajectory.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 12), .completed)
    }
    @MainActor func testLaunchDismissTabForegroundAndNextColdLaunch() {
        app.launch()
        let watch = app.buttons["featured.watch"], dismiss = app.buttons["featured.dismiss"]
        XCTAssertTrue(watch.waitForExistence(timeout: 10)); XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThan(dismiss.frame.midX, watch.frame.midX)
        XCTAssertGreaterThanOrEqual(watch.frame.height, 44); XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        XCTAssertFalse(app.otherElements["trajectory.chart"].exists); shot("refinement-launch-card")
        dismiss.tap(); XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(watch.exists); XCTAssertFalse(app.buttons["playoffs.close"].exists)
        app.buttons["Game Recaps"].firstMatch.tap()
        XCTAssertFalse(watch.exists); shot("refinement-dismiss-preserves-navigation")
        app.terminate(); app.launch(); XCTAssertTrue(watch.waitForExistence(timeout: 10))
    }
    @MainActor func testWatchReplayDuringAfterForegroundAndBack() {
        app.launch(); watch()
        let replay = app.buttons["trajectory.replay"]; reveal(replay)
        XCTAssertGreaterThanOrEqual(replay.frame.height, 44); XCTAssertGreaterThanOrEqual(replay.frame.width, 44)
        replay.tap(); replay.tap() // The second tap resets an in-progress sequence.
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["featured.watch"].exists)
        complete(); reveal(app.otherElements["trajectory.chart"]); shot("refinement-sequential-finished")
        reveal(replay); replay.tap(); complete() // Replay after completion.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["featured.watch"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["trajectory.chart"].exists)
        app.buttons["featured.dismiss"].tap(); XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 5))
    }
    @MainActor func testOnboardingCompletesBeforeOfferingStory() {
        app.launchArguments = ["-reset-team-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let choose = app.buttons["Choose your first team to follow"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["featured.watch"].exists)
        reveal(choose); choose.tap()
        let menu = app.collectionViews.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let firstVisibleTeam = menu.buttons.firstMatch
        XCTAssertTrue(firstVisibleTeam.waitForExistence(timeout: 5)); firstVisibleTeam.tap()
        let follow = app.buttons["FOLLOW THIS TEAM"]; reveal(follow); follow.tap()
        XCTAssertTrue(app.buttons["featured.watch"].waitForExistence(timeout: 10))
        XCTAssertFalse(follow.exists); XCTAssertFalse(app.buttons["playoffs.close"].exists)
        shot("refinement-after-onboarding")
    }
    @MainActor func testLargestTextReducedMotionAndReplay() {
        app.launchArguments[app.launchArguments.count - 1] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        app.launch(); shot("refinement-largest-text-card"); watch(); complete()
        let chart = app.otherElements["trajectory.chart"]; reveal(chart)
        XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX); XCTAssertGreaterThanOrEqual(chart.frame.minX, 0)
        XCTAssertTrue(chart.value as? String == "2024: 41 Cumulative wins. 2025: 60 Cumulative wins. 2026: 84 Cumulative wins. June 23, 2026 · 41–37. Chicago matched all 41 wins from 2024 before halfway through the season.")
        shot("refinement-largest-text-static-comparison")
        let replay = app.buttons["trajectory.replay"]; reveal(replay); replay.tap(); complete()
        XCTAssertFalse(app.buttons["trajectory.pause"].exists)
        let data = app.buttons["trajectory.data"]; reveal(data); data.tap()
        XCTAssertTrue(app.navigationBars["Explore the data"].waitForExistence(timeout: 5))
    }
    @MainActor func testMilestoneArrowPreview() {
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = "5.66296296296"
        app.launch(); watch(); reveal(app.otherElements["trajectory.chart"])
        XCTAssertTrue(app.staticTexts["trajectory.progress"].label.contains("78"))
        shot("refinement-game78-comparison-arrow")
    }
}
