import XCTest
@testable import ClosetWise

/// Checks the purchase check against the sample closet (16 pieces, 11 logged outfits:
/// mostly neutrals, loose wide-leg jeans, regular/relaxed tops, everyday casual).
final class PurchaseCheckEngineTests: XCTestCase {
    private let closet = SampleData.wardrobe
    private var learned: LearnedStyle { StyleLearner.learn(items: closet, logs: SampleData.outfitLogs) }
    private var signals: StyleSignals { StyleSignals(learned: learned) }

    private var ribbedTop: WardrobeItem { SampleData.exampleProducts[0] }
    private var camelTrousers: WardrobeItem { SampleData.exampleProducts[1] }
    private var redSkinnyJeans: WardrobeItem { SampleData.exampleProducts[2] }
    private var choreJacket: WardrobeItem { SampleData.exampleProducts[3] }

    // MARK: Duplicates

    func testNearIdenticalTopIsFlagged() {
        let r = PurchaseCheckEngine.check(ribbedTop, closet: closet, signals: signals)
        XCTAssertEqual(r.duplicates.first?.item.id, SampleData.blackTop.id, "closest match should be the black ribbed top already owned")
        XCTAssertGreaterThanOrEqual(r.duplicates.first?.score ?? 0, 0.85)
        XCTAssertEqual(r.duplicates.first?.level, "Nearly identical")
        XCTAssertTrue(r.duplicates.first?.reasons.contains("same colour") == true)
        XCTAssertTrue(r.duplicates.first?.reasons.contains("same fit") == true)
        XCTAssertEqual(r.verdict, .probablySkip)
    }

    func testOtherBlackTopsAreSimilarButNotIdentical() {
        let r = PurchaseCheckEngine.check(ribbedTop, closet: closet, signals: signals)
        let ids = Set(r.duplicates.map(\.item.id))
        XCTAssertTrue(ids.contains(SampleData.blackTee.id))
        XCTAssertTrue(ids.contains(SampleData.tank.id))
        for d in r.duplicates where d.item.id != SampleData.blackTop.id {
            XCTAssertLessThan(d.score, 0.85, "\(d.item.name) shouldn't count as identical")
        }
    }

    func testDifferentColourOrTypeIsNotADuplicate() {
        let r = PurchaseCheckEngine.check(ribbedTop, closet: closet, signals: signals)
        let ids = Set(r.duplicates.map(\.item.id))
        for item in [SampleData.knitSweater, SampleData.greyHoodie, SampleData.skyOxford, SampleData.whiteShirt, SampleData.wideLegJeans] {
            XCTAssertFalse(ids.contains(item.id), "\(item.name) should not be similar to a black ribbed top")
        }
    }

    func testSameCutDifferentColourTrousersAreNotDuplicates() {
        let r = PurchaseCheckEngine.check(camelTrousers, closet: closet, signals: signals)
        XCTAssertTrue(r.duplicates.isEmpty, "camel wool trousers aren't a duplicate of blue jeans: \(r.duplicates.map { ($0.item.name, $0.score) })")
    }

    func testSimilarityIsSymmetric() {
        for a in closet { for b in closet {
            XCTAssertEqual(PurchaseCheckEngine.similarity(a, b).0, PurchaseCheckEngine.similarity(b, a).0, accuracy: 1e-9)
        } }
    }

    func testOwnedItemsAreNotDuplicatesOfEachOther() {
        // The sample closet has no real duplicates; only the black basics should come close.
        for a in closet { for b in closet where a.id != b.id {
            let s = PurchaseCheckEngine.similarity(a, b).0
            XCTAssertLessThan(s, 0.85, "\(a.name) vs \(b.name) scored \(s)")
        } }
    }

    // MARK: Compatibility

    func testCompatibilityCountsOutfitsAndNewOnes() {
        let r = PurchaseCheckEngine.check(camelTrousers, closet: closet, signals: signals)
        XCTAssertGreaterThan(r.outfits.count, 4)
        XCTAssertEqual(r.newOutfitCount, r.outfits.count, "no duplicate → every outfit is new")
        XCTAssertTrue(r.compatible.contains { $0.id == SampleData.whiteShirt.id })

        let dup = PurchaseCheckEngine.check(ribbedTop, closet: closet, signals: signals)
        XCTAssertLessThan(dup.newOutfitCount, dup.outfits.count, "the owned black top already makes most of these outfits")
    }

    func testClashingColoursAreExcluded() {
        let r = PurchaseCheckEngine.check(redSkinnyJeans, closet: closet, signals: signals)
        let ids = Set(r.compatible.map(\.id))
        XCTAssertFalse(ids.contains(SampleData.oliveKnit.id), "red with olive green shouldn't be suggested")
        XCTAssertTrue(ids.contains(SampleData.blackTee.id), "red jeans with a black tee is fine")
    }

    func testDressinessGapExcludesPairing() {
        XCTAssertLessThan(PurchaseCheckEngine.pairScore(SampleData.greyHoodie, SampleData.blackBlazer), 0)
    }

    // MARK: Style fit

    func testStyleFitFollowsWhatYouWear() {
        let camel = PurchaseCheckEngine.styleFit(camelTrousers, signals: signals)
        let red = PurchaseCheckEngine.styleFit(redSkinnyJeans, signals: signals)
        XCTAssertGreaterThan(camel.score, red.score)
        XCTAssertTrue(camel.reasons.contains { $0.positive && $0.text.contains("Loose") }, "\(camel.reasons)")
        XCTAssertTrue(red.reasons.contains { !$0.positive && $0.text.contains("Tight") }, "\(red.reasons)")
    }

    func testStatedPreferencesChangeStyleFit() {
        var prefs = StylePreferences()
        prefs.avoidColors = ["red"]
        prefs.fits = ["bottom": .loose]
        prefs.about = "Nothing too tight."
        let stated = StyleSignals(preferences: prefs, learned: learned)
        let before = PurchaseCheckEngine.styleFit(redSkinnyJeans, signals: signals).score
        let after = PurchaseCheckEngine.styleFit(redSkinnyJeans, signals: stated)
        XCTAssertLessThan(after.score, before)
        XCTAssertLessThan(after.score, 40)
        XCTAssertTrue(after.reasons.contains { $0.text.contains("colour you avoid") })
        XCTAssertTrue(after.reasons.contains { $0.text.contains("prefer loose") })
        XCTAssertEqual(PurchaseCheckEngine.check(redSkinnyJeans, closet: closet, signals: stated).verdict, .limitedGain)
    }

    func testVibesAffectStyleFit() {
        var prefs = StylePreferences()
        prefs.vibes = ["Workwear"]
        let withVibe = PurchaseCheckEngine.styleFit(choreJacket, signals: StyleSignals(preferences: prefs, learned: learned))
        let without = PurchaseCheckEngine.styleFit(choreJacket, signals: signals)
        XCTAssertGreaterThan(withVibe.score, without.score)
    }

    func testDuplicatesLowerPredictedWear() {
        let dup = PurchaseCheckEngine.check(ribbedTop, closet: closet, signals: signals)
        var fresh = ribbedTop
        fresh.color = "yellow"; fresh.hex = 0xE6C65C
        let unique = PurchaseCheckEngine.check(fresh, closet: closet, signals: signals)
        XCTAssertLessThan(dup.predictedWearsPerYear, unique.predictedWearsPerYear)
    }

    // MARK: Intake

    func testAttributeGuesserReadsListingText() {
        let item = AttributeGuesser.guess(ProductDraft(name: "Relaxed Wide Leg Trousers", colorText: "Camel", material: "Wool blend"))
        XCTAssertEqual(item.kind, .trousers)
        XCTAssertEqual(item.category, .bottom)
        XCTAssertEqual(item.color, "beige")
        XCTAssertEqual(item.silhouette, "wide-leg")
        XCTAssertTrue([.loose, .relaxed].contains(item.fit))

        let tee = AttributeGuesser.guess(ProductDraft(name: "Oversized Boxy T-Shirt", colorText: "Charcoal"))
        XCTAssertEqual(tee.kind, .tee)
        XCTAssertEqual(tee.fit, .oversized)
        XCTAssertEqual(tee.color, "grey")
    }

    func testLinkParserReadsJSONLD() {
        let html = """
        <html><head><meta property="og:site_name" content="Example Store">
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"BreadcrumbList"},
        {"@type":"Product","name":"Ribbed Long Sleeve Top","color":"Black","material":"Cotton rib",
         "image":["https://cdn.example.com/top.jpg"],"brand":{"@type":"Brand","name":"Example"},
         "offers":{"@type":"Offer","price":"38.00","priceCurrency":"USD"}}]}</script></head></html>
        """
        let d = ProductLinkFetcher.parse(html: html, baseURL: URL(string: "https://example.com/p/1"))
        XCTAssertEqual(d.name, "Ribbed Long Sleeve Top")
        XCTAssertEqual(d.price, Decimal(string: "38.00"))
        XCTAssertEqual(d.colorText, "Black")
        XCTAssertEqual(d.imageURL?.absoluteString, "https://cdn.example.com/top.jpg")
        XCTAssertEqual(d.store, "Example Store")
        let item = AttributeGuesser.guess(d)
        XCTAssertEqual(item.kind, .knit)
        XCTAssertEqual(item.color, "black")
        XCTAssertEqual(PurchaseCheckEngine.check(item, closet: closet, signals: signals).duplicates.first?.item.id, SampleData.blackTop.id)
    }

    func testLinkParserFallsBackToOpenGraph() {
        let html = #"<meta property="og:title" content="Linen Shirt &amp; More"><meta property="og:image" content="/img/shirt.jpg"><meta property="product:price:amount" content="45">"#
        let d = ProductLinkFetcher.parse(html: html, baseURL: URL(string: "https://shop.example.com/x"))
        XCTAssertEqual(d.name, "Linen Shirt & More")
        XCTAssertEqual(d.price, 45)
        XCTAssertEqual(d.imageURL?.absoluteString, "https://shop.example.com/img/shirt.jpg")
    }

    func testColourMath() {
        XCTAssertLessThan(ColorMath.deltaE(0x1D1D1F, 0x18181A), 3)
        XCTAssertGreaterThan(ColorMath.deltaE(0x1D1D1F, 0xF2F1EC), 80)
        XCTAssertEqual(ColorMath.normalize("Dark Wash Indigo")?.name, "denim")
        XCTAssertEqual(ColorMath.normalize("Ecru")?.name, "cream")
    }
}

final class DominantColorTests: XCTestCase {
    /// A black garment on a mint background (no cut-out) should read as black, not the background.
    func testIgnoresPlainBackground() {
        let size = CGSize(width: 200, height: 220)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.90, green: 0.96, blue: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(x: 50, y: 40, width: 100, height: 140))
        }
        XCTAssertEqual(DominantColor.of(image)?.name, "black")
    }

    func testCutoutUsesOnlyOpaquePixels() {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { ctx in
            UIColor(red: 0.36, green: 0.50, blue: 0.66, alpha: 1).setFill()   // denim blue
            ctx.fill(CGRect(x: 30, y: 10, width: 40, height: 80))
        }
        XCTAssertEqual(DominantColor.of(image)?.name, "denim")
    }
}
