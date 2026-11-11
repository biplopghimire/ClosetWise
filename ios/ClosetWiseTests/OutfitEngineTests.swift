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
    func testGarmentsAreDrawnOnceAndReused() {
        let tee = SampleData.blackTee
        let slot = OutfitBoard.slot(for: tee.category, size: 170)
        let first = GarmentSprites.shared.image(tee, size: slot)
        XCTAssertNotNil(first)
        XCTAssertTrue(GarmentSprites.shared.image(tee, size: slot) === first, "second card reuses the same picture")
    }

    // MARK: Engine v2

    private let dress = WardrobeItem(name: "Black slip dress", category: .dress, kind: .skirt, color: "black", hex: 0x1D1D1F,
                                     material: "satin", fit: .fitted, style: "smart casual", formality: 3)
    private let cap = WardrobeItem(name: "Navy cap", category: .accessory, kind: .shoes, color: "navy", hex: 0x23324F,
                                   material: "cotton", fit: .regular, style: "casual", formality: 1)

    func testEveryPieceGetsOutfitsIncludingDressesAndAccessories() {
        let closet = SampleData.wardrobe + [dress, cap]
        for item in closet {
            let outfits = OutfitEngine.outfits(with: item, from: closet)
            XCTAssertGreaterThanOrEqual(outfits.count, 3, "\(item.name) should have outfits")
            XCTAssertTrue(outfits.allSatisfy { $0.contains(item) }, "every outfit for \(item.name) includes it")
            XCTAssertEqual(Set(outfits.map(\.id)).count, outfits.count)
        }
        let dressLooks = OutfitEngine.outfits(with: dress, from: closet)
        XCTAssertTrue(dressLooks.allSatisfy { $0.top == nil && $0.bottom == nil && $0.dress?.id == dress.id })
    }

    func testOutfitsWithAPieceIgnoreTodaysWeather() {
        let shorts = SampleData.denimShorts
        let freezing = StyleSignals(weather: weather(feels: -5))
        XCTAssertFalse(OutfitEngine.outfits(with: shorts, from: closet, signals: freezing).isEmpty,
                       "an item's own page still shows how to wear it")
    }

    func testStyleOutweighsUnwornPieces() {
        // The olive knit and denim shorts are the longest unworn; a minimal-neutrals user should still get neutrals first.
        var prefs = StylePreferences()
        prefs.vibes = ["Minimal"]
        prefs.avoidColors = ["green"]
        let top = OutfitEngine.rank(from: closet, signals: StyleSignals(preferences: prefs)).prefix(10)
        XCTAssertFalse(top.contains { $0.pieces.contains { $0.color == "green" } }, "an avoided colour stays out of the top ideas")
    }

    func testShoesMatchTheRestOfTheOutfit() {
        let polished = OutfitEngine.rank(from: closet, signals: StyleSignals(occasion: .smart)).prefix(8)
        XCTAssertFalse(polished.isEmpty)
        XCTAssertTrue(polished.allSatisfy { o in o.shoes.formality >= 2 }, "smart looks don't pair with flip-flop-level shoes")
        XCTAssertFalse(polished.contains { $0.pieces.contains { $0.kind == .hoodie } }, "no hoodies in smart looks")
        let lounge = OutfitEngine.rank(from: closet, signals: StyleSignals(occasion: .lounge))
        XCTAssertTrue(lounge.allSatisfy { $0.pieces.allSatisfy { $0.formality <= 2 } })
    }

    func testDailySuggestionRotatesButIsStableWithinADay() {
        let days = (0..<10).map { OutfitEngine.suggest(from: closet, limit: 1, seed: UInt64($0)).first!.id }
        XCTAssertGreaterThanOrEqual(Set(days).count, 4, "Home shows different outfits on different days")
        XCTAssertEqual(OutfitEngine.suggest(from: closet, limit: 1, seed: 3).first?.id,
                       OutfitEngine.suggest(from: closet, limit: 1, seed: 3).first?.id, "same day, same outfit")
    }

    func testRecentlyWornOutfitsSink() {
        let first = OutfitEngine.rank(from: closet)[0]
        let signals = StyleSignals(recentlyWorn: [Outfit.comboKey(first.pieces.filter { $0.category != .accessory }.map(\.id))])
        XCTAssertNotEqual(OutfitEngine.rank(from: closet, signals: signals).first?.id, first.id)
    }

    func testLockingAPieceAndSwappingOneSlot() {
        let tee = SampleData.blackTee
        let looks = OutfitEngine.best(from: closet, locked: [tee], limit: 10, seed: 1)
        XCTAssertGreaterThanOrEqual(looks.count, 5)
        XCTAssertTrue(looks.allSatisfy { $0.top?.id == tee.id }, "Shuffle keeps the locked tee")
        XCTAssertNotEqual(looks.map(\.id), OutfitEngine.best(from: closet, locked: [tee], limit: 10, seed: 2).map(\.id),
                          "a new shuffle gives a different order")

        let look = looks[0]
        let shoes = OutfitEngine.alternatives(for: .shoes, in: look, from: closet)
        XCTAssertEqual(Set(shoes.map(\.id)), Set(closet.filter { $0.category == .shoes }.map(\.id)), "every pair of shoes is reachable")
        let swapped = OutfitEngine.replacing(.shoes, with: shoes.last!, in: look, from: closet)
        XCTAssertEqual(swapped?.shoes.id, shoes.last!.id)
        XCTAssertEqual(swapped?.top?.id, tee.id, "swapping shoes leaves the rest alone")

        let withDress = OutfitEngine.replacing(.dress, with: dress, in: look, from: closet + [dress])
        XCTAssertNil(withDress?.top)
        XCTAssertNil(withDress?.bottom)
        XCTAssertEqual(withDress?.dress?.id, dress.id, "choosing a dress replaces the top and bottom")
    }

    func testPicksAreGenuinelyDifferentOutfits() {
        let ranked = OutfitEngine.rank(from: closet)
        let picks = OutfitEngine.picks(from: ranked, limit: 10)
        XCTAssertGreaterThanOrEqual(picks.count, 5)
        XCTAssertEqual(picks.first?.id, ranked.first?.id, "pick #1 is the top-ranked outfit")
        let core = { (o: Outfit) in Set(o.pieces.filter { [.top, .bottom, .dress, .shoes].contains($0.category) }.map(\.id)) }
        for (i, a) in picks.enumerated() {
            for b in picks.prefix(i) {
                XCTAssertGreaterThanOrEqual(core(a).subtracting(core(b)).count, 2,
                                            "\(a.pieces.map(\.name)) is too close to \(b.pieces.map(\.name))")
            }
        }

        // With the top locked, picks still change both the bottom and the shoes.
        let tee = SampleData.blackTee
        let locked = OutfitEngine.picks(from: OutfitEngine.ranking(from: closet, locked: [tee]).outfits, fixed: [tee.id], limit: 10)
        XCTAssertTrue(locked.allSatisfy { $0.top?.id == tee.id })
        XCTAssertGreaterThanOrEqual(locked.count, 2)
    }

    func testWarmthTargetsRiseAsItGetsColder() {
        XCTAssertLessThan(Warmth.target(forC: 30), Warmth.target(forC: 18))
        XCTAssertLessThan(Warmth.target(forC: 18), Warmth.target(forC: 2))
        XCTAssertGreaterThan(Warmth.of(SampleData.wardrobe.first { $0.kind == .coat }!), Warmth.of(SampleData.blackTee))
    }
}

final class GuidedCameraTests: XCTestCase {
    func testCropMapsTheOnScreenFrameOntoThePhoto() {
        // A 3000×4000 photo shown aspect-fill on a 400×800 screen: scale 0.2, 50 pt cut off each side.
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 4000), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { ctx in UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 4000)) }
        let frame = CGRect(x: 100, y: 200, width: 200, height: 300)
        let cropped = GuidedCamera.crop(photo, to: frame, screen: CGSize(width: 400, height: 800))
        XCTAssertNotNil(cropped)
        // Frame plus a 6% margin each side, in photo pixels: (200+24)/0.2 × (300+36)/0.2.
        XCTAssertEqual(cropped!.size.width, 1120, accuracy: 2)
        XCTAssertEqual(cropped!.size.height, 1680, accuracy: 2)
    }

    func testEveryGuideHasAShapeAndAType() {
        for guide in CaptureGuide.allCases {
            XCTAssertGreaterThan(guide.frame.width, 0.4)
            XCTAssertGreaterThan(guide.frame.height, 0.4)
            XCTAssertNotNil(OutfitSlot(guide.category))
        }
    }
}
