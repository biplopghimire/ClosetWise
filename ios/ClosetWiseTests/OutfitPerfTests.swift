import XCTest
@testable import ClosetWise

final class OutfitPerfTests: XCTestCase {
    /// A big closet (150 pieces) still ranks quickly enough to build the feed.
    func testRankingABigClosetIsFast() {
        var big: [WardrobeItem] = []
        for i in 0..<10 { big += SampleData.wardrobe.map { var x = $0; x.id = UUID(); x.name += " \(i)"; return x } }
        let start = Date()
        let outfits = OutfitEngine.rank(from: big, signals: StyleSignals())
        let seconds = Date().timeIntervalSince(start)
        print("RANK big closet: \(big.count) items → \(outfits.count) outfits in \(String(format: "%.2f", seconds))s")
        XCTAssertLessThan(seconds, 1.5)
    }
}
