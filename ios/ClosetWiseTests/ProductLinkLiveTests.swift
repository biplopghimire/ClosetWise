import XCTest
@testable import ClosetWise

/// Reads real product pages over the network. Off by default; run with
/// `TEST_RUNNER_CLOSETWISE_LIVE_TESTS=1 xcodebuild test … -only-testing:ClosetWiseTests/ProductLinkLiveTests`.
/// Stops before the Gemini step, so no account is created.
final class ProductLinkLiveTests: XCTestCase {
    private let links = [
        ("Zara (JavaScript page)", "https://www.zara.com/us/en/100-linen-regular-fit-shirt-p01957102.html"),
        ("Uniqlo (blocks plain fetches)", "https://www.uniqlo.com/us/en/products/E455365-000/00"),
        ("H&M (blocks plain fetches)", "https://www2.hm.com/en_us/productpage.1368757001.html"),
        ("ASOS", "https://www.asos.com/us/4505/4505-shrunken-muscle-fit-cotton-baby-tee-with-quick-dry-finish-in-black/prd/209902149"),
        ("Gap", "https://www.gap.com/browse/product.do?pid=1184982032"),
        ("Hollister", "https://www.hollisterco.com/shop/us/p/heavyweight-boxy-camo-pattern-t-shirt-60556819"),
        ("Abercrombie", "https://www.abercrombie.com/shop/us/p/classic-essential-tee-61737319"),
        ("Ralph Lauren", "https://www.ralphlauren.com/men-clothing-polo-shirts/custom-fit-mesh-polo-shirt/391628.html"),
        ("Banana Republic", "https://bananarepublic.gap.com/browse/product.do?pid=755610052"),
        ("Share text", "Love this 😍 https://www.asos.com/us/collusion/collusion-sheer-long-sleeve-fitted-t-shirt-in-camo/prd/211836013 via ASOS"),
    ]

    @MainActor
    func testRealProductLinks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOSETWISE_LIVE_TESTS"] == "1", "live network test")
        var report: [String] = []
        for (name, link) in links {
            let start = Date()
            do {
                let (page, image) = try await ProductLinkFetcher.read(link)
                let draft = ProductLinkFetcher.draft(from: page)
                report.append(String(format: "✅ %@ [%@ %.1fs] name=%@ price=%@ hasPrice=%@ structured=%d image=%@ text=%d",
                                     name, page.via, Date().timeIntervalSince(start), String(draft.name.prefix(50)),
                                     draft.price.map { "\($0)" } ?? "–", page.hasPrice ? "yes" : "no", page.structured.count,
                                     image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none", page.text.count))
            } catch {
                report.append(String(format: "❌ %@ [%.1fs] %@", name, Date().timeIntervalSince(start), error.localizedDescription))
            }
        }
        print("LIVE LINK REPORT\n" + report.joined(separator: "\n"))
    }

    func testFindsTheLinkInPastedText() {
        XCTAssertEqual(ProductLinkFetcher.extractURL("Love this https://www.zara.com/us/en/x-p1.html via Zara")?.absoluteString,
                       "https://www.zara.com/us/en/x-p1.html")
        XCTAssertEqual(ProductLinkFetcher.extractURL("zara.com/us/en/x-p1.html")?.scheme, "https")
        XCTAssertNil(ProductLinkFetcher.extractURL("just some words"))
        XCTAssertNil(ProductLinkFetcher.extractURL("me@example.com"))
    }

    /// The "Share" links from the Hollister and Abercrombie apps open the app, not the page; the page is inside them.
    func testUnwrapsStoreAppShareLinks() {
        let hollister = "LOVE this from Hollister!\nhttps://hollisterco.app.link?$deeplink_path=product%2Fcollection%2F680471%2Fkic%2FKIC%5F334%2D6078%2D00369%2D900&$desktop_url=https%3A%2F%2Fwww.hollisterco.com%2Fshop%2Fus%2Fp%2Fgraphic%2Dsuper%2Dbaggy%2Dsweatpants%2D61713324%3Fofp%3Dtrue&$og_image_url=https%3A%2F%2Fimg.hollisterco.com%2Fis%2Fimage%2Fanf%2FKIC%5F334%2D6078%2D00369%2D900%5Fprod1%3Fpolicy%3Dproduct%2Dsmall&$og_title=Hollister%20Feel%20Good%20Sport%20Blocking%20Super%20Baggy%20Sweatpants"
        XCTAssertEqual(ProductLinkFetcher.extractURL(hollister)?.absoluteString,
                       "https://www.hollisterco.com/shop/us/p/graphic-super-baggy-sweatpants-61713324?ofp=true")
        let abercrombie = "LOVE this from Abercrombie!\nhttps://abercrombie.app.link?$deeplink_path=product%2Fcollection%2F705607%2Fkic%2FKIC%5F122%2D6687%2D01766%2D310&$desktop_url=https%3A%2F%2Fwww.abercrombie.com%2Fshop%2Fus%2Fp%2Fessential%2Dfleece%2Dpolo%2D63199333%3Fofp%3Dtrue&$og_image_url=https%3A%2F%2Fimg.abercrombie.com%2Fis%2Fimage%2Fanf%2FKIC%5F122%2D6687%2D01766%2D310%5Fprod1%3Fpolicy%3Dproduct%2Dsmall&$og_title=Essential%20Polo%20Sweatshirt"
        XCTAssertEqual(ProductLinkFetcher.extractURL(abercrombie)?.absoluteString,
                       "https://www.abercrombie.com/shop/us/p/essential-fleece-polo-63199333?ofp=true")
        // A short app link with nothing inside stays as is (it's resolved over the network).
        XCTAssertEqual(ProductLinkFetcher.extractURL("https://hollisterco.app.link/AbC123")?.host, "hollisterco.app.link")
        XCTAssertTrue(ProductLinkFetcher.isAppLinkHost("abercrombie.app.link"))
        XCTAssertFalse(ProductLinkFetcher.isAppLinkHost("www.abercrombie.com"))
    }

    func testGuessesKindFromStoreNames() {
        XCTAssertEqual(AttributeGuesser.guessKind("feel good sport blocking super baggy sweatpants"), .trousers)
        XCTAssertEqual(AttributeGuesser.guessKind("essential polo sweatshirt"), .knit)
        XCTAssertEqual(AttributeGuesser.guessKind("essential popover hoodie"), .hoodie)
        XCTAssertEqual(AttributeGuesser.guessKind("linen blend shirt"), .shirt)
    }
}
