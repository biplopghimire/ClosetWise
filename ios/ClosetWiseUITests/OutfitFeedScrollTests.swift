import XCTest

/// Measures how smoothly the outfit ideas feed scrolls (hitches = dropped/late frames).
final class OutfitFeedScrollTests: XCTestCase {
    func testOutfitIdeasScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-measureHitches"]
        app.launch()

        app.tabBars.buttons["Closet"].tap()
        let ideas = app.buttons["Outfit ideas"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 10))
        ideas.tap()
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        sleep(2)   // first page settles

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = 8
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            for _ in 0..<4 { feed.swipeUp(velocity: .fast) }
            stopMeasuring()
        }
        sleep(3)   // let the monitor log its final numbers
    }
}
