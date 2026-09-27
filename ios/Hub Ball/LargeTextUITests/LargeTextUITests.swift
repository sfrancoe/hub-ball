import XCTest
import UIKit

final class LargeTextUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(bundleIdentifier: "com.sfrancoe.HubBall")
    }

    override func tearDownWithError() throws {
        capture("final")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    private func launch(_ route: String = "", size: String = "UICTContentSizeCategoryAccessibilityXXXL", team: String = "boston") {
        app.launchArguments = ["-hubCompletedTeamOnboarding", "YES", "-hubSelectedTeam", team]
        if !size.isEmpty { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        if !route.isEmpty { app.launchArguments.append(route) }
        app.launch()
    }

    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        // The window frame updates before UIKit finishes its rotation transform.
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func scroll(_ direction: String = "up") {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: direction == "up" ? 0.82 : 0.52))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: direction == "up" ? 0.52 : 0.82))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    @discardableResult
    private func reveal(_ element: XCUIElement, attempts: Int = 50) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            if element.exists && element.frame.maxY < app.frame.minY + app.frame.height * 0.35 {
                scroll("down")
            } else {
                scroll()
            }
        }
        return element.exists && element.isHittable
    }

    private func revealHitter(_ element: XCUIElement) -> Bool {
        for _ in 0..<20 {
            let footer = app.buttons["hitter.replay"]
            let close = app.buttons["hitter.close"]
            let upper = close.exists ? close.frame.maxY : app.frame.minY + 60
            let lower = footer.exists ? footer.frame.minY - 8 : app.frame.maxY - 30
            let isFixed = ["hitter.replay", "hitter.music", "hitter.close"].contains(element.identifier)
            // SwiftUI can report an offscreen scroll child as hittable underneath
            // a safe-area bar. Check its actual tap center before interacting.
            if element.exists && element.isHittable && (isFixed || (element.frame.midY > upper && element.frame.midY < lower)) { return true }
            let needsDown = element.exists && element.frame.midY <= upper
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: needsDown ? 0.22 : 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: needsDown ? 0.45 : 0.22))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return false
    }

    func testHitterStoryPlaybackAndAllSeasons() {
        launch("-show-hitter-story", size: "UICTContentSizeCategoryL")
        XCTAssertTrue(app.buttons["hitter.launch"].waitForExistence(timeout: 10))
        capture("hitter-launch")
        XCTAssertEqual(app.switches["hitter.launchMusic"].value as? String, "0")
        app.buttons["hitter.launch"].tap()
        XCTAssertFalse(app.buttons["hitter.launch"].exists)
        XCTAssertTrue(app.staticTexts["hitter.complete"].waitForExistence(timeout: 13))
        XCTAssertTrue(app.staticTexts["hitter.snapshot"].label.contains("Sept. 27, 2026"))
        XCTAssertTrue(app.staticTexts["hitter.complete"].label.contains("Will it end at six again?"))
        capture("hitter-complete")
        let chart = app.otherElements["hitter.chart"]
        XCTAssertTrue(revealHitter(chart))
        let counts = [23,30,16,26,29,30,21,25,24,15,22,24,21,17,20,23,21,32,46,38,44,31,46,51,49,44,30,36,36,30,33,36,31,35,19,23,22,23,15,19,24,23,14,19,20,12,10,9,7,6,6]
        for (index, count) in counts.enumerated() {
            let x = 27 + CGFloat(index) / CGFloat(counts.count - 1) * (chart.frame.width - 43)
            chart.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: 140)).tap()
            XCTAssertEqual(app.otherElements["hitter.selection"].label, "\(1976 + index)\(index == counts.count - 1 ? " YTD" : ""): \(count) qualified hitters")
        }
        XCTAssertTrue(revealHitter(app.buttons["hitter.music"]))
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music off"))
        app.buttons["hitter.music"].tap()
        if app.buttons["hitter.music"].label.contains("Music on") {
            app.buttons["hitter.music"].tap()
        } else {
            XCTAssertTrue(app.staticTexts["hitter.audioUnavailable"].exists, "Audio failure must be visible and leave the story usable")
        }
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music off"))
        app.buttons["hitter.replay"].tap()
        XCTAssertTrue(app.staticTexts["hitter.building"].exists)
        XCTAssertTrue(app.staticTexts["hitter.complete"].waitForExistence(timeout: 13))
        capture("hitter-replay-and-controls")
        XCTAssertTrue(revealHitter(app.buttons["hitter.methodology"]))
        app.buttons["hitter.methodology"].tap()
        XCTAssertTrue(app.navigationBars["How we count"].waitForExistence(timeout: 5))
        capture("hitter-methodology")
    }

    func testHitterStoryGlobalNavigation() {
        launch(size: "UICTContentSizeCategoryL", team: "chicago-cubs")
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 10))
        capture("hitter-header")
        app.buttons["stories.open"].tap()
        XCTAssertTrue(app.buttons["stories.hitter"].waitForExistence(timeout: 5))
        capture("hitter-library")
        app.buttons["stories.hitter"].tap()
        XCTAssertTrue(app.buttons["hitter.launch"].waitForExistence(timeout: 5))
        app.buttons["hitter.close"].tap()
        XCTAssertTrue(app.buttons["stories.close"].waitForExistence(timeout: 5))
        app.buttons["stories.close"].tap()
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 5))
    }

    func testHitterStoryLargeText() {
        launch("-show-hitter-story")
        XCTAssertTrue(revealHitter(app.buttons["hitter.launch"]))
        capture("hitter-large-launch")
        app.buttons["hitter.launch"].tap()
        XCTAssertTrue(revealHitter(app.otherElements["hitter.chart"]))
        capture("hitter-large-chart")
        XCTAssertTrue(revealHitter(app.buttons["hitter.replay"]))
        XCTAssertTrue(revealHitter(app.buttons["hitter.music"]))
        capture("hitter-large-controls")
    }

    func testHitterSoundLifecycleAndCompactHeader() {
        launch(size: "UICTContentSizeCategoryAccessibilityXXXL", team: "arizona")
        XCTAssertTrue(app.buttons["stories.open"].waitForExistence(timeout: 10))
        for identifier in ["stories.open", "playoffs.open", "Switch team"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        }
        capture("hitter-compact-large-header")
        app.terminate()
        launch("-show-hitter-story", size: "UICTContentSizeCategoryL")
        XCTAssertTrue(app.switches["hitter.launchMusic"].waitForExistence(timeout: 10))
        XCTAssertTrue(revealHitter(app.switches["hitter.launchMusic"]))
        app.switches["hitter.launchMusic"].tap()
        XCTAssertTrue(revealHitter(app.buttons["hitter.launch"]))
        app.buttons["hitter.launch"].tap()
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music on") || app.staticTexts["hitter.audioUnavailable"].exists)
        capture("hitter-compact-playing")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["hitter.music"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music off"))
        XCTAssertTrue(app.staticTexts["hitter.complete"].exists)
        capture("hitter-background-stopped")
        let chart = app.otherElements["hitter.chart"]
        XCTAssertTrue(revealHitter(chart))
        chart.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 27, dy: 140)).tap()
        XCTAssertEqual(app.otherElements["hitter.selection"].label, "1976: 23 qualified hitters")
        capture("hitter-compact-selection")
    }

    func testHitterAudiblePlayback() throws {
        launch("-show-hitter-story", size: "UICTContentSizeCategoryL")
        XCTAssertTrue(app.buttons["hitter.launch"].waitForExistence(timeout: 10))
        app.buttons["hitter.launch"].tap()
        app.buttons["hitter.music"].tap()
        if app.staticTexts["hitter.audioUnavailable"].exists {
            throw XCTSkip("The simulator audio route rejects playback; generated WAV decoding is covered separately. Verify audible playback on a working route or device.")
        }
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music on"))
        app.buttons["hitter.music"].tap()
        XCTAssertTrue(app.buttons["hitter.music"].label.contains("Music off"))
    }

    func testPlayoffsBracketAndGlobalNavigation() {
        launch(size: "UICTContentSizeCategoryL")
        let open = app.buttons["playoffs.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["October"].exists, "Playoffs is not a team page")
        open.tap()
        XCTAssertTrue(app.staticTexts["2026 PLAYOFFS"].waitForExistence(timeout: 5))
        let bracket = app.scrollViews["playoffs.bracket"]
        XCTAssertTrue(bracket.waitForExistence(timeout: 30))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bracket."))
        XCTAssertEqual(cards.count, 11, "Every series must be present together")
        for card in cards.allElementsBoundByIndex {
            XCTAssertTrue(card.isHittable, "Full bracket visible: \(card.identifier)")
        }
        capture("playoffs-full-bracket")
        app.buttons["bracket.al-wild-card-b"].tap()
        XCTAssertTrue(app.navigationBars["Wild Card"].waitForExistence(timeout: 5))
        capture("playoffs-series-details")
        app.buttons["series.close"].tap()
        app.buttons["playoffs.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Switch team"].exists)
        app.buttons["Switch team"].tap()
        app.buttons["Page Order"].tap()
        XCTAssertFalse(app.staticTexts["October"].exists, "Old saved page orders must omit October")
        XCTAssertFalse(app.cells.containing(.staticText, identifier: "2026 Playoffs").firstMatch.exists, "Global destination is not reorderable as a team page")
        capture("playoffs-team-page-order")
    }

    func testPlayoffsLargeTextAndLandscape() {
        launch("-show-october")
        XCTAssertTrue(app.scrollViews["playoffs.bracket"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bracket.")).count, 11)
        capture("playoffs-large-text")
        app.buttons["playoffs.close"].tap()
        XCTAssertTrue(app.buttons["playoffs.open"].isHittable)
        XCTAssertTrue(app.buttons["Switch team"].isHittable)
        capture("playoffs-large-text-navigation")
        app.terminate()
        launch("-show-october", size: "UICTContentSizeCategoryL")
        rotate(.landscapeLeft)
        XCTAssertTrue(app.scrollViews["playoffs.bracket"].waitForExistence(timeout: 30))
        capture("playoffs-landscape")
    }

    func testCareerBattingRecordsAndTotals() {
        launch("-show-player=701350")
        XCTAssertTrue(app.staticTexts["Roman Anthony"].firstMatch.waitForExistence(timeout: 30))
        let metric = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "At bats")).firstMatch
        XCTAssertTrue(reveal(metric), "A real batting season's metrics must be reachable")
        capture("batting-season")
        let totals = app.staticTexts["Career totals"].firstMatch
        XCTAssertTrue(reveal(totals), "Career totals must be reachable")
        capture("batting-totals")
        verifyTotals("career.batting.totals", labels: ["Games", "At bats", "Runs", "Hits", "Home runs", "Triples", "Doubles", "Runs batted in", "Stolen bases", "Walks", "Strikeouts", "Batting average", "On-base percentage", "Slugging percentage", "OPS"])
        capture("batting-totals-final-metrics")
    }

    func testCareerPitchingRecordsAndTotals() {
        launch("-show-player=801139")
        XCTAssertTrue(app.staticTexts["Payton Tolle"].firstMatch.waitForExistence(timeout: 30))
        let metric = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Innings pitched")).firstMatch
        XCTAssertTrue(reveal(metric), "A real pitching season's metrics must be reachable")
        capture("pitching-season")
        XCTAssertTrue(reveal(app.staticTexts["Career totals"].firstMatch))
        capture("pitching-totals")
        verifyTotals("career.pitching.totals", labels: ["Games", "Games started", "Wins", "Losses", "Saves", "Innings pitched", "Hits", "Earned runs", "Home runs", "Walks", "Strikeouts", "Earned run average", "WHIP"])
        capture("pitching-totals-final-metrics")
    }

    private func verifyTotals(_ id: String, labels: [String]) {
        var seen = Set<String>()
        for _ in 0..<45 {
            let metrics = app.otherElements[id].descendants(matching: .other).allElementsBoundByIndex
            for metric in metrics where labels.contains(metric.label) && metric.isHittable
                && metric.frame.minY >= app.buttons["Page"].frame.maxY + 50
                && metric.frame.maxY <= app.frame.maxY - 8 {
                XCTAssertFalse((metric.value as? String ?? "").isEmpty, "Career total \(metric.label) must expose its value")
                seen.insert(metric.label)
            }
            if seen.isSuperset(of: labels) { return }
            scroll()
        }
        XCTFail("Career totals not reached: \(Set(labels).subtracting(seen).sorted())")
    }

    func testRecapScrollingAndPlayerNavigation() {
        launch("-show-recent")
        XCTAssertTrue(app.buttons["Game"].waitForExistence(timeout: 30))
        let teamHeader = app.staticTexts["Team"].firstMatch
        XCTAssertTrue(reveal(teamHeader, attempts: 15))
        capture("recap-innings-start")
        let score = app.scrollViews.allElementsBoundByIndex.first { $0.frame.height < 400 && $0.frame.width > 100 && $0.isHittable }
        // Save the tree before choosing the nested table, for diagnosable failures.
        XCTAssertNotNil(score, "Inning scroll view must be reachable")
        if let score {
            for _ in 0..<12 { score.swipeLeft() }
        }
        capture("recap-innings-end")
        let lob = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", ", Left on base,")).firstMatch
        XCTAssertTrue(lob.exists && lob.isHittable, "LOB totals must be visible after horizontal scrolling")
        XCTAssertTrue((app.buttons["Page"].value as? String ?? "").hasPrefix("Game Recaps"))
        XCTAssertTrue(reveal(app.staticTexts["Batting"].firstMatch, attempts: 20))
        capture("recap-batting")
        let player = app.buttons["Roman Anthony"].firstMatch
        XCTAssertTrue(reveal(player, attempts: 12))
        player.tap()
        XCTAssertTrue(app.staticTexts["Roman Anthony"].firstMatch.waitForExistence(timeout: 15))
        capture("recap-player-detail")
    }

    private func scrollMenu() {
        let menu = app.collectionViews.firstMatch
        XCTAssertTrue(menu.exists, "A native menu must be open before scrolling")
        let bar = menu.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar")).firstMatch
        let visible = bar.exists ? bar.frame : menu.frame.intersection(app.frame)
        let origin = menu.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: menu.frame.width / 2, dy: visible.maxY - menu.frame.minY - 25))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: menu.frame.width / 2, dy: visible.minY - menu.frame.minY + 25)))
    }

    private func selectPage(_ title: String) {
        if app.buttons["Page"].exists {
            app.buttons["Page"].tap()
            let option = app.buttons[title].firstMatch
            for _ in 0..<10 {
                if option.exists { break }
                scrollMenu()
            }
            XCTAssertTrue(option.exists, "Page menu must reach \(title)")
            option.tap()
            XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 10))
            XCTAssertTrue((app.buttons["Page"].value as? String ?? "").hasPrefix(title))
        } else {
            let option = app.buttons[title].firstMatch
            XCTAssertTrue(option.exists)
            let strip = app.scrollViews.containing(.button, identifier: title).firstMatch
            for _ in 0..<8 {
                if option.frame.minX >= app.frame.minX && option.frame.maxX <= app.frame.maxX { break }
                if option.frame.minX < app.frame.minX { strip.swipeRight() } else { strip.swipeLeft() }
            }
            XCTAssertGreaterThanOrEqual(option.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(option.frame.maxX, app.frame.maxX)
            option.tap()
        }
    }

    private func sections(size: String) {
        launch(size: size)
        XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 10) || app.buttons["Home"].exists)
        for title in ["Home", "Game Recaps", "Standings", "Schedule", "Newspapers", "X Posts", "Players", "Pitching", "Leaders", "Stories"] {
            selectPage(title)
            capture(title + "-top")
            for _ in 0..<3 { scroll() }
            capture(title + "-scrolled")
            rotate(.landscapeLeft)
            capture(title + "-landscape")
            rotate(.portrait)
        }
    }

    func testAllSectionsAccessibility5() {
        sections(size: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    func testAllSectionsDefault() {
        sections(size: "UICTContentSizeCategoryL")
    }

    func testSearchKeyboardRotationAndBackground() {
        launch("-show-players")
        let search = app.textFields["Search players"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Anthony")
        XCTAssertEqual(search.value as? String, "Anthony")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("search-keyboard")
        rotate(.landscapeLeft)
        XCTAssertEqual(search.value as? String, "Anthony")
        capture("search-keyboard-landscape")
        rotate(.portrait)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(search.value as? String, "Anthony")
        capture("search-restored")
    }

    func testHomeRunChaseProjection() {
        launch("-show-home-run-chase")
        let fourth = app.buttons["Chapter 4"].firstMatch
        XCTAssertTrue(reveal(fourth, attempts: 30))
        fourth.tap()
        let slider = app.sliders.firstMatch
        XCTAssertTrue(reveal(slider, attempts: 30))
        capture("chase-projection-before")
        slider.adjust(toNormalizedSliderPosition: 0.7)
        let selected = slider.value as? String
        capture("chase-projection-after")
        rotate(.landscapeLeft)
        XCTAssertEqual(slider.value as? String, selected)
        capture("chase-projection-landscape")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(slider.value as? String, selected)
    }


    func testBrewersStoryControlsAndSources() {
        launch("-show-stories", team: "milwaukee")
        let story = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "WHO BUILT")).firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 20))
        XCTAssertTrue(reveal(story, attempts: 12))
        story.tap()
        let next = app.buttons["Next play"]
        XCTAssertTrue(reveal(next, attempts: 20))
        next.tap()
        let progress = app.sliders["Game progress, play by play"]
        XCTAssertTrue(progress.exists)
        XCTAssertNotEqual(progress.value as? String, "Before first pitch")
        capture("brewers-first-play")
        XCTAssertTrue(reveal(progress, attempts: 10))
        progress.adjust(toNormalizedSliderPosition: 1)
        capture("brewers-final-play")
        for _ in 0..<12 {
            if app.buttons["03 THE 42"].isHittable { break }
            scroll("down")
        }
        app.buttons["03 THE 42"].tap()
        XCTAssertTrue(reveal(app.staticTexts["Cumulative run producers"], attempts: 15))
        capture("brewers-combined-contributors")
        let sources = app.buttons["Box scores & story sources"]
        XCTAssertTrue(reveal(sources, attempts: 60))
        capture("brewers-bottom-controls")
        sources.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        capture("brewers-sources")
        app.buttons["Done"].tap()
    }

    func testBostonStoryPlayback() {
        launch("-show-stories")
        let nine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "NINE PITCHES")).firstMatch
        XCTAssertTrue(nine.waitForExistence(timeout: 20))
        nine.tap()
        let play = app.buttons["Play inning"]
        XCTAssertTrue(reveal(play, attempts: 30))
        capture("nine-pitches-controls")
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.buttons["Pause"].exists, "Backgrounding must pause the story")
        capture("nine-pitches-paused")
        app.terminate()
        launch("-show-stories")
        let four = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "FOUR ROADS")).firstMatch
        XCTAssertTrue(reveal(four, attempts: 15))
        four.tap()
        let graphPlay = app.buttons["Play"].firstMatch
        XCTAssertTrue(reveal(graphPlay, attempts: 25))
        graphPlay.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(reveal(app.buttons["Restart"], attempts: 8))
        app.buttons["Restart"].tap()
        XCTAssertTrue(reveal(app.buttons["4×"], attempts: 12))
        app.buttons["4×"].tap()
        capture("four-roads-controls")
    }

    func testTextClippingAudit() throws {
        launch()
        XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 20))
        try app.performAccessibilityAudit(for: [.textClipped])
        selectPage("Players")
        try app.performAccessibilityAudit(for: [.textClipped])
        selectPage("Standings")
        try app.performAccessibilityAudit(for: [.textClipped])
    }


    func testLiveTextSizeRetainsState() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HUBBALL_LIVE_SIZE_TEST"] == "1",
                          "Run through scripts/test_large_text_live_size.py for real system text-size changes")
        launch("-show-players", size: "")
        let search = app.textFields["Search players"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Anthony")
        requestSize("accessibility-extra-extra-extra-large", expanded: true)
        XCTAssertEqual(search.value as? String, "Anthony")
        capture("live-size-filter-access5")
        requestSize("large", expanded: false)
        XCTAssertEqual(search.value as? String, "Anthony")
        capture("live-size-filter-default")
        app.terminate()
        launch("-show-home-run-chase", size: "")
        XCTAssertTrue(reveal(app.buttons["Chapter 4"].firstMatch, attempts: 25))
        app.buttons["Chapter 4"].firstMatch.tap()
        let slider = app.sliders.firstMatch
        XCTAssertTrue(reveal(slider, attempts: 20))
        slider.adjust(toNormalizedSliderPosition: 0.7)
        let value = slider.value as? String
        requestSize("accessibility-extra-extra-extra-large", expanded: true)
        XCTAssertTrue(reveal(slider, attempts: 20))
        XCTAssertEqual(slider.value as? String, value)
        capture("live-size-chase-access5")
        requestSize("large", expanded: false)
        XCTAssertEqual(slider.value as? String, value)
    }

    private func requestSize(_ size: String, expanded: Bool) {
        print("HUBBALL_SIZE_REQUEST:" + size)
        fflush(stdout)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["Page"].exists == expanded
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed)
    }

    func testSelectorsAndDetailSheets() {
        launch()
        XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 20))
        selectPage("Standings")
        let mode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Standings view")).firstMatch
        mode.tap()
        app.buttons["Wild Card"].tap()
        capture("standings-wild-card")
        XCTAssertTrue(mode.label.contains("Wild Card"))
        selectPage("Pitching")
        let role = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pitcher role")).firstMatch
        XCTAssertTrue(role.waitForExistence(timeout: 20))
        role.tap()
        app.buttons["Relievers"].tap()
        XCTAssertTrue(role.label.contains("Relievers"))
        let actual = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Actual:")).firstMatch
        XCTAssertTrue(reveal(actual, attempts: 35))
        capture("pitching-actual-forecast")
        selectPage("Leaders")
        let scope = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Leaderboard scope")).firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 20))
        scope.tap()
        app.buttons["MLB"].tap()
        let detail = app.buttons["Category details & source"].firstMatch
        XCTAssertTrue(reveal(detail, attempts: 35))
        detail.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        capture("leaders-detail")
        app.buttons["Close"].tap()
    }


    func testPlayerMenusAndStoryCards() throws {
        launch("-show-players")
        let order = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Player order")).firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 30))
        order.tap()
        app.buttons["Age"].tap()
        XCTAssertEqual(order.value as? String, "Age, ascending")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sort direction")).firstMatch.tap()
        app.buttons["Descending"].tap()
        XCTAssertEqual(order.value as? String, "Age, descending")
        let position = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Player position")).firstMatch
        position.tap()
        app.buttons["Pitchers"].tap()
        XCTAssertTrue(position.label.contains("Pitchers"))
        capture("players-menus")
        try app.performAccessibilityAudit(for: [.textClipped])
        selectPage("Stories")
        let nine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "NINE PITCHES")).firstMatch
        XCTAssertTrue(reveal(nine, attempts: 10))
        scroll()
        scroll()
        capture("story-card-expanded")
        try app.performAccessibilityAudit(for: [.textClipped])
    }

    func testIPadNarrowWindow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad-only window test")
        launch("-show-players")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Player order")).firstMatch.waitForExistence(timeout: 30))
        if app.frame.width < 650 { restoreIPadWindow() }
        let original = app.frame
        defer {
            restoreIPadWindow()
            XCTAssertEqual(app.frame.width, original.width, accuracy: 2, "Restore the original full-width window")
        }
        let corner = app.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
        let smaller = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.8))
        corner.press(forDuration: 0.5, thenDragTo: smaller, withVelocity: .slow, thenHoldForDuration: 0.5)
        Thread.sleep(forTimeInterval: 1)
        capture("ipad-resize-attempt")
        guard app.frame.width < original.width - 100 else {
            throw XCTSkip("The simulator window did not resize through its corner control")
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Player order")).firstMatch.isHittable)
        capture("ipad-narrow-window")
        for _ in 0..<3 { scroll() }
        capture("ipad-narrow-window-scrolled")
        selectPage("Game Recaps")
        for _ in 0..<3 { scroll() }
        capture("ipad-narrow-recap")
        selectPage("Standings")
        capture("ipad-narrow-standings")
    }



    func testIntermediateTextSizes() {
        for size in ["UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityXL"] {
            launch("-show-players", size: size)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Player order")).firstMatch.waitForExistence(timeout: 30))
            capture(size + "-players")
            selectPage("Game Recaps")
            XCTAssertTrue(app.buttons["Game"].waitForExistence(timeout: 30))
            for _ in 0..<3 { scroll() }
            capture(size + "-recap")
            selectPage("Standings")
            capture(size + "-standings")
            app.terminate()
        }
    }

    func testSettingsMenus() {
        launch()
        XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 20))
        app.buttons["Page"].tap()
        let settings = app.buttons["Teams and settings"]
        for _ in 0..<10 {
            if settings.exists { break }
            scrollMenu()
        }
        settings.tap()
        let section = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Settings section")).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        section.tap()
        app.buttons["Page Order"].tap()
        XCTAssertTrue(section.label.contains("Page Order"))
        for _ in 0..<3 { scroll() }
        capture("settings-page-order")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Page"].waitForExistence(timeout: 10))
    }

    func testOnboardingTextSizesAndLandscape() {
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityXL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments = ["-reset-team-onboarding",
                                   "-UIPreferredContentSizeCategoryName", size]
            app.launch()
            let choose = app.buttons["Choose your first team to follow"]
            XCTAssertTrue(reveal(choose, attempts: 25))
            capture(size + "-onboarding")
            choose.tap()
            let arizona = app.buttons["Arizona Diamondbacks"].firstMatch
            for _ in 0..<30 {
                if arizona.exists { break }
                scrollMenu()
            }
            XCTAssertTrue(arizona.exists)
            arizona.tap()
            XCTAssertEqual(choose.value as? String, "Arizona Diamondbacks")
            rotate(.landscapeLeft)
            let follow = app.buttons["FOLLOW THIS TEAM"]
            XCTAssertTrue(reveal(follow, attempts: 30))
            for _ in 0..<10 {
                if follow.frame.maxY <= app.frame.maxY - 8 { break }
                scroll()
            }
            XCTAssertLessThanOrEqual(follow.frame.maxY, app.frame.maxY - 8)
            XCTAssertGreaterThanOrEqual(follow.frame.minY, app.frame.minY)
            capture(size + "-onboarding-landscape-follow")
            XCTAssertTrue(follow.isEnabled)
            follow.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !self.app.buttons["FOLLOW THIS TEAM"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            rotate(.portrait)
            app.terminate()
        }
    }

    func testCareerScopeSortingAndReturn() {
        launch("-show-players")
        let search = app.textFields["Search players"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        search.typeText("Anthony\n")
        let player = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Roman Anthony, number")).firstMatch
        XCTAssertTrue(reveal(player, attempts: 15))
        player.tap()
        let both = app.buttons["Both"].firstMatch
        XCTAssertTrue(reveal(both, attempts: 30))
        both.tap()
        let year = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Year")).firstMatch
        XCTAssertTrue(reveal(year, attempts: 15))
        year.tap()
        capture("career-both-leagues-sorted")
        rotate(.landscapeLeft)
        capture("career-both-leagues-landscape")
        rotate(.portrait)
        XCUIDevice.shared.press(.home)
        app.activate()
        app.buttons["Back to players"].tap()
        XCTAssertEqual(search.value as? String, "Anthony")
        capture("career-return-filter-retained")
    }

    private func restoreIPadWindow() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let zoom = system.buttons["Zoom-button"]
        if !zoom.exists {
            let controls = system.buttons["window-controls:com.sfrancoe.HubBall"]
            XCTAssertTrue(controls.waitForExistence(timeout: 10))
            controls.tap()
        }
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.tap()
        Thread.sleep(forTimeInterval: 1)
    }

}
