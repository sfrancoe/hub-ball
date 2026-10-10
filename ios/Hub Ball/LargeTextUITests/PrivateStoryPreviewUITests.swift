import XCTest

final class PrivateStoryPreviewUITests: XCTestCase {
    private var app: XCUIApplication!
    private let ids = ["preview-oct09-sixth", "preview-oct09-brewers", "preview-oct09-baker"]
    private let titles = ["The Sixth That Saved October", "Four Games. Never Breathing Room.", "Four Saves. Then Forty-One."]
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
        app.launchEnvironment = ["HUB_STORY_ROOT": "http://127.0.0.1:1/data", "HUB_STORY_CACHE_NAME": "private-preview-" + UUID().uuidString.lowercased(), "HUB_API_ROOT": "http://127.0.0.1:1", "HUB_DATA_ROOT": "http://127.0.0.1:1/data"]
        app.launchArguments = ["-hubCompletedTeamOnboarding", "YES", "-hubSelectedTeam", "rays", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["HUB_STORY_LEGACY_LAUNCH"] = "1"
    }
    override func tearDownWithError() throws { app.terminate() }
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
    private func shot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func compareFromLibrary() {
        let compare = app.buttons["stories.private-previews"]; XCTAssertTrue(compare.waitForExistence(timeout: 10)); reveal(compare); compare.tap()
        XCTAssertTrue(app.navigationBars["October 9 previews"].waitForExistence(timeout: 5))
        for id in ids { XCTAssertTrue(app.buttons["stories.private.\(id)"].exists) }
    }
    private func open(_ index: Int) {
        let card = app.buttons["stories.private.\(ids[index])"]; reveal(card); card.tap()
        XCTAssertTrue(app.otherElements["trajectory.chart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["remote.title"].label, titles[index])
    }
    private func complete() {
        let predicate = NSPredicate(format: "label == %@", "Chart complete")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["trajectory.status"])], timeout: 12), .completed)
    }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor func testCompareAllRefreshDismissReopenAndColdOffline() {
        app.launch()
        let dismiss = app.buttons["featured.dismiss"]; XCTAssertTrue(dismiss.waitForExistence(timeout: 10)); dismiss.tap()
        app.buttons["stories.open"].tap(); compareFromLibrary(); shot("private-comparison-list")
        for index in ids.indices {
            open(index)
            let replay = app.buttons["trajectory.replay"]; reveal(replay); replay.tap(); replay.tap()
            complete(); reveal(app.otherElements["trajectory.chart"]); shot("private-\(ids[index])-finished")
            if index == 2 { XCTAssertEqual(app.staticTexts["trajectory.conclusion"].label,"Then he closed all three ALDS wins.") }
            reveal(replay); replay.tap(); complete(); back()
        }
        back()
        let refresh = app.buttons["stories.refresh"]; reveal(refresh); refresh.tap()
        XCTAssertTrue(app.staticTexts["stories.offline"].waitForExistence(timeout: 10)); compareFromLibrary()
        app.buttons["stories.private.close"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 5))
        app.buttons["stories.open"].tap(); compareFromLibrary()
        app.terminate(); app.launch()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10)); dismiss.tap()
        app.buttons["stories.open"].tap(); compareFromLibrary(); open(2); complete()
    }
    @MainActor func testLargestTextReducedMotionSourcesAndData() {
        app.launchArguments += ["-show-story-library"]
        app.launchArguments[5] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        app.launch(); compareFromLibrary()
        for index in ids.indices {
            open(index); complete()
            let chart = app.otherElements["trajectory.chart"]; reveal(chart)
            XCTAssertGreaterThanOrEqual(chart.frame.minX, 0); XCTAssertLessThanOrEqual(chart.frame.maxX, app.frame.maxX)
            shot("private-largest-\(ids[index])")
            let replay = app.buttons["trajectory.replay"]; reveal(replay); replay.tap(); complete()
            XCTAssertFalse(app.buttons["trajectory.pause"].exists)
            let data = app.buttons["trajectory.data"]; reveal(data); data.tap()
            XCTAssertTrue(app.navigationBars["Explore the data"].waitForExistence(timeout: 5)); app.buttons["trajectory.data.close"].tap()
            let sources = app.buttons["trajectory.sources"]; reveal(sources); sources.tap()
            XCTAssertTrue(app.navigationBars["Sources & methodology"].waitForExistence(timeout: 5)); app.buttons["trajectory.sources.close"].tap()
            back()
        }
    }
    @MainActor func testSixthInningHoldShowsCompletedTopSixth() {
        app.launchArguments += ["-show-story-library"]
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = "4.2"
        app.launch(); compareFromLibrary(); open(0); reveal(app.otherElements["trajectory.chart"])
        XCTAssertTrue(app.staticTexts["trajectory.progress"].label.contains("5.5"))
        XCTAssertEqual(app.staticTexts["trajectory.emphasis"].label,"Six in the sixth. October stays open.")
        shot("private-cleveland-sixth-hold")
    }
    @MainActor func testBakerYearsAreReadable() {
        app.launchArguments += ["-show-story-library"]
        app.launchEnvironment["HUB_STORY_REDUCE_MOTION"] = "1"
        app.launch(); compareFromLibrary(); open(2); complete()
        reveal(app.otherElements["trajectory.chart"])
        XCTAssertEqual(app.staticTexts["trajectory.progress"].label,"Season: 2026")
        XCTAssertTrue(app.otherElements["trajectory.chart"].label.contains("Season, 2021 to 2026"))
        shot("private-baker-readable-year-labels")
    }
    @MainActor func testMilwaukeeSequentialPreview() {
        app.launchArguments += ["-show-story-library"]
        app.launchEnvironment["HUB_STORY_PREVIEW_TIME"] = "4.75"
        app.launch(); compareFromLibrary(); open(1); reveal(app.otherElements["trajectory.chart"])
        XCTAssertTrue(app.staticTexts["trajectory.progress"].label.contains("Game 3"))
        shot("private-milwaukee-third-game")
    }
}
