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
    private func scroll(_ feed: OutfitFeed, to target: Int) async throws {
        for _ in 0..<2000 where feed.count < target {
            feed.loadMore()
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    @MainActor
    func testFeedIsEndlessVariedAndDropsDislikes() async throws {
        let signals = StyleSignals(weather: weather(feels: 18))
        let feed = OutfitFeed()
        feed.reset(items: closet, signals: signals)
        try await scroll(feed, to: 10)
        XCTAssertGreaterThanOrEqual(feed.count, 10, "first page arrives from the background ranking")

        let first = feed.rounds[0].entries[0].outfit
        feed.drop(disliked: [first.id])
        XCTAssertFalse(feed.rounds.flatMap(\.entries).contains { $0.outfit.id == first.id })

        // Scroll well past everything the closet can make: the feed keeps going.
        let total = OutfitEngine.rank(from: closet, signals: signals).count
        try await scroll(feed, to: total + 40)
        XCTAssertGreaterThanOrEqual(feed.count, total + 40, "the feed never runs dry")
        XCTAssertGreaterThan(feed.rounds.count, 1, "a new round starts once everything has been shown")
        XCTAssertFalse(feed.rounds.flatMap(\.entries).contains { $0.outfit.id == first.id }, "turned-down outfits stay gone")

        let firstRound = feed.rounds[0].entries.map(\.outfit.id)
        XCTAssertEqual(Set(firstRound).count, firstRound.count, "no repeats within a round")
        XCTAssertEqual(Set(feed.rounds.flatMap(\.entries).map(\.id)).count, feed.count, "every card has its own id")
        let shown = feed.rounds[0].entries.map(\.outfit)
        let similar = zip(shown, shown.dropFirst()).prefix(20)
            .filter { Set($0.pieces.map(\.id)).intersection($1.pieces.map(\.id)).count >= 2 }.count
        XCTAssertLessThanOrEqual(similar, 4, "neighbours rarely share most of their pieces")
    }

    @MainActor
    func testBigClosetFeedKeepsFindingNewOutfits() async throws {
        var big: [WardrobeItem] = []
        for i in 0..<8 { big += SampleData.wardrobe.map { var x = $0; x.id = UUID(); x.name += " \(i)"; return x } }
        let feed = OutfitFeed()
        feed.reset(items: big, signals: StyleSignals())
        try await scroll(feed, to: 400)
        let ids = feed.rounds[0].entries.map(\.outfit.id)
        XCTAssertGreaterThanOrEqual(ids.count, 400)
        XCTAssertEqual(Set(ids).count, ids.count, "a big closet keeps producing outfits it hasn't shown")
    }

    @MainActor
    func testGarmentsAreDrawnOnceAndReused() {
        let tee = SampleData.blackTee
        let slot = OutfitBoard.slot(for: tee.category, size: 170)
        let first = GarmentSprites.shared.image(tee, size: slot)
        XCTAssertNotNil(first)
        XCTAssertTrue(GarmentSprites.shared.image(tee, size: slot) === first, "second card reuses the same picture")
    }

    func testWarmthTargetsRiseAsItGetsColder() {
        XCTAssertLessThan(Warmth.target(forC: 30), Warmth.target(forC: 18))
        XCTAssertLessThan(Warmth.target(forC: 18), Warmth.target(forC: 2))
        XCTAssertGreaterThan(Warmth.of(SampleData.wardrobe.first { $0.kind == .coat }!), Warmth.of(SampleData.blackTee))
    }
}
