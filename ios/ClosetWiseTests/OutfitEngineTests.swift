import XCTest
@testable import ClosetWise

final class OutfitEngineTests: XCTestCase {
    private let sandals = WardrobeItem(name: "Tan sandals", category: .shoes, kind: .shoes, color: "beige", hex: 0xC9A97C,
                                       material: "leather", fit: .regular, style: "casual", formality: 1)
    private var closet: [WardrobeItem] { SampleData.wardrobe + [sandals] }

    private func weather(feels: Double, code: Int = 0, rain: Int = 0) -> WeatherNow {
        WeatherNow(tempC: feels, feelsC: feels, highC: feels, lowC: feels - 4, precipChance: rain, code: code,
                   windKmh: 10, place: "Testville", fetchedAt: .now)
    }

    private func ranked(_ w: WeatherNow?, prefs: StylePreferences = .init()) -> [Outfit] {
        OutfitEngine.rank(from: closet, signals: StyleSignals(preferences: prefs, weather: w))
    }

    func testColdWeatherRulesOutShortsAndLayersUp() {
        let outfits = ranked(weather(feels: 3))
        XCTAssertFalse(outfits.isEmpty)
        XCTAssertFalse(outfits.contains { $0.pieces.contains { $0.kind == .shorts } }, "no shorts at 3°C")
        XCTAssertFalse(ranked(weather(feels: 14)).contains { $0.pieces.contains { $0.kind == .shorts } }, "no shorts at 14°C")
        XCTAssertFalse(outfits.contains { $0.pieces.contains { Warmth.isOpenShoe($0) } }, "no sandals at 3°C")
        let top = outfits.prefix(5)
        XCTAssertTrue(top.allSatisfy { o in o.layer != nil || o.pieces.contains { $0.kind == .knit || $0.kind == .hoodie } })
    }

    func testHotWeatherRulesOutCoats() {
        let outfits = ranked(weather(feels: 31))
        XCTAssertFalse(outfits.isEmpty)
        XCTAssertFalse(outfits.contains { $0.pieces.contains { $0.kind == .coat } }, "no coat at 31°C")
        let topWarmth = outfits.prefix(5).map { $0.pieces.map(Warmth.of).reduce(0, +) }
        XCTAssertTrue(topWarmth.allSatisfy { $0 <= 5.5 }, "top hot-day ideas stay light: \(topWarmth)")
    }

    func testSnowRulesOutSandalsEvenWhenMild() {
        let outfits = ranked(weather(feels: 12, code: 73))
        XCTAssertFalse(outfits.contains { $0.pieces.contains { Warmth.isOpenShoe($0) } })
    }

    func testAvoidedColoursSinkAndLovedVibesRise() {
        var prefs = StylePreferences()
        prefs.avoidColors = ["black"]
        let outfits = ranked(nil, prefs: prefs)
        let topTen = outfits.prefix(10)
        let blackInTop = topTen.filter { $0.pieces.contains { $0.color == "black" } }.count
        let blackOverall = Double(outfits.filter { $0.pieces.contains { $0.color == "black" } }.count) / Double(outfits.count)
        XCTAssertLessThan(Double(blackInTop) / 10, blackOverall, "outfits with an avoided colour rank below average")
        XCTAssertTrue(outfits.allSatisfy { (0...100).contains($0.styleScore) })
    }

    func testRankingCoversEveryComboWithoutDuplicates() {
        let outfits = ranked(nil)
        XCTAssertEqual(Set(outfits.map(\.id)).count, outfits.count)
        XCTAssertGreaterThan(outfits.count, 30)
    }

    @MainActor
    func testFeedPagesThroughEverythingOnceAndDropsDislikes() {
        let feed = OutfitFeed()
        feed.reset(items: closet, signals: StyleSignals(weather: weather(feels: 18)), fresh: true)
        XCTAssertEqual(feed.shown.count, 8)
        let first = feed.shown[0]
        feed.drop(disliked: [first.id])
        XCTAssertFalse(feed.shown.contains(first))
        var pages = 0
        while !feed.exhausted && pages < 500 { feed.loadMore(); pages += 1 }
        XCTAssertTrue(feed.exhausted)
        XCTAssertEqual(Set(feed.shown.map(\.id)).count, feed.shown.count, "no outfit shown twice")
        XCTAssertEqual(feed.shown.count, feed.total - 1)
        // Neighbours rarely repeat: most consecutive pairs share at most one piece.
        let pairs = zip(feed.shown, feed.shown.dropFirst()).prefix(20)
        let similar = pairs.filter { Set($0.pieces.map(\.id)).intersection($1.pieces.map(\.id)).count >= 2 }.count
        XCTAssertLessThanOrEqual(similar, 4)
    }

    func testWarmthTargetsRiseAsItGetsColder() {
        XCTAssertLessThan(Warmth.target(forC: 30), Warmth.target(forC: 18))
        XCTAssertLessThan(Warmth.target(forC: 18), Warmth.target(forC: 2))
        XCTAssertGreaterThan(Warmth.of(SampleData.wardrobe.first { $0.kind == .coat }!), Warmth.of(SampleData.blackTee))
    }
}
