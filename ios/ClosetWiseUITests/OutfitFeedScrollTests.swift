import XCTest

/// Measures how smoothly the Outfits builder swipes (hitches = dropped/late frames).
final class OutfitFeedScrollTests: XCTestCase {
    func testOutfitBuilderSwiping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-measureHitches"]
        app.launch()

        app.tabBars.buttons["Outfits"].tap()
        let shuffle = app.buttons["Shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 10))
        let rows = app.scrollViews
        sleep(1)

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = 8
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            for i in 0..<4 { rows.element(boundBy: 1 + i % 2).swipeLeft(velocity: .fast) }
            shuffle.tap()
            stopMeasuring()
        }
        sleep(3)   // let the monitor log its final numbers
    }
}
