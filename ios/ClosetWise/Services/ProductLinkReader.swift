import Foundation
import UIKit
import WebKit

/// What the phone could read off a product page, sent to ClosetWise (Gemini) to make sense of.
struct ProductPage: Encodable {
    var url: String
    var title: String
    /// schema.org JSON-LD blocks that describe a product.
    var structured: [String] = []
    /// og:title, og:description, og:site_name, og:image, product:price:amount, product:price:currency, h1 …
    var meta: [String: String] = [:]
    /// Visible page text, trimmed.
    var text: String = ""

    /// Candidate product photos, best first (not sent; the chosen photo is attached as an image).
    var imageURLs: [URL] = []
    /// How the page was read: "quick" (plain download) or "browser" (hidden WebKit view). Not sent.
    var via = "quick"

    enum CodingKeys: String, CodingKey { case url, title, structured, meta, text }

    var store: String? {
        meta["og:site_name"] ?? URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "")
    }

    /// Every product photo the listing offers (the gallery from structured data, the share image, the
    /// big pictures on the page), de-duplicated, best first.
    var galleryPhotos: [URL] {
        let base = URL(string: url)
        var urls: [URL] = []
        for block in structured {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
                  let product = ProductLinkFetcher.findProduct(json) else { continue }
            urls += ProductLinkFetcher.imageURLs(product["image"], base: base)
            for variant in (product["hasVariant"] as? [[String: Any]] ?? []).prefix(3) {
                urls += ProductLinkFetcher.imageURLs(variant["image"], base: base)
            }
        }
        urls += [meta["og:image"].flatMap { URL(string: $0, relativeTo: base) }].compactMap { $0 } + imageURLs
        var seen = Set<String>()
        return urls.filter { $0.scheme?.hasPrefix("http") == true && seen.insert($0.absoluteString).inserted }.prefix(10).map { $0 }
    }

    /// Enough to work with: a product in the structured data, or a title plus a picture.
    var hasProductSignals: Bool {
        !structured.isEmpty || ((meta["og:title"] ?? meta["h1"]) != nil && (!imageURLs.isEmpty || meta["og:image"] != nil))
    }

    /// The listing's own price: from structured data, price meta tags, or the page's price element —
    /// not any dollar amount in the text ("free shipping over $49" isn't the price).
    var hasPrice: Bool { ProductLinkFetcher.draft(from: self).price != nil }

    /// Looks like a bot check or an error page rather than a product.
    var looksBlocked: Bool {
        let probe = (title + " " + text.prefix(600)).lowercased()
        return ["access denied", "are you a robot", "captcha", "just a moment", "verify you are human", "unusual traffic",
                "request blocked", "forbidden", "pardon our interruption", "page not found", "404"].contains(where: probe.contains)
    }
}

/// Reads a product link: finds the link in whatever was pasted, loads the page (quickly when the store
/// serves plain HTML; in a hidden browser when the page is built by JavaScript or guarded against bots),
/// and pulls out the product data and photo.
enum ProductLinkFetcher {
    enum FetchError: LocalizedError {
        case badURL, blocked(String), nothingFound(String), notAProduct

        var errorDescription: String? {
            switch self {
            case .badURL: "That doesn't look like a product link. Copy the link from the store's Share button and paste it here."
            case .blocked(let store): "\(store) doesn't let apps read its pages. Take a screenshot of the product and use Photo instead."
            case .nothingFound(let store): "Couldn't find a product on that \(store) page. Open the product itself (not a search or category), or use a screenshot."
            case .notAProduct: "That page doesn't look like a single clothing item. Open the product itself, or use a screenshot."
            }
        }
    }

    // MARK: Finding the link

    /// The first web link in pasted text ("Check this out! https://…"), adding https:// if it was left off.
    static func extractURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           var url = match.url {
            // "zara.com/…" pasted without a scheme comes back as http://; stores all serve https.
            if url.scheme?.lowercased() == "http", !trimmed.lowercased().contains("http://") {
                url = URL(string: "https://" + url.absoluteString.dropFirst("http://".count)) ?? url
            }
            if ["http", "https"].contains(url.scheme?.lowercased()), url.host?.contains(".") == true { return url }
        }
        return nil
    }

    // MARK: Reading the page

    /// The page's product data and its best photo.
    @MainActor
    static func read(_ text: String) async throws -> (ProductPage, UIImage?) {
        guard let url = extractURL(text) else { throw FetchError.badURL }
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "That store"

        // Fast path: many stores serve the product data in plain HTML.
        var page = await quickRead(url)
        if page == nil || page?.hasProductSignals == false || page?.looksBlocked == true {
            // Slow path: let a real browser engine build the page.
            page = await WebPageReader().read(url) ?? page
        } else if let quick = page, !quick.hasPrice {
            // Some stores fill in the price with JavaScript after the page arrives.
            if let rendered = await WebPageReader().read(url, timeout: 9), rendered.hasProductSignals, rendered.hasPrice {
                page = merge(quick, rendered)
            }
        }
        guard let page else { throw FetchError.blocked(host) }
        if !page.hasProductSignals {
            throw page.looksBlocked || page.text.count < 200 ? FetchError.blocked(page.store ?? host) : FetchError.nothingFound(page.store ?? host)
        }
        let og = page.meta["og:image"].flatMap { URL(string: $0, relativeTo: url) }
        let candidates = Array(page.imageURLs.prefix(1)) + [og].compactMap { $0 } + page.imageURLs.dropFirst()
        let image = await downloadImage(candidates, referer: URL(string: page.url) ?? url)
        return (page, image)
    }

    /// The rendered page's price and text with the quick read's structured data and photos.
    private static func merge(_ quick: ProductPage, _ rendered: ProductPage) -> ProductPage {
        var page = rendered
        page.structured = Array(Set(quick.structured + rendered.structured))
        page.meta = quick.meta.merging(rendered.meta) { _, new in new }
        page.imageURLs = quick.imageURLs + rendered.imageURLs
        if rendered.text.count < quick.text.count / 2 { page.text = rendered.text + "\n" + quick.text }
        page.text = String(page.text.prefix(8000))
        return page
    }

    private static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func quickRead(_ url: URL) async -> ProductPage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let html = String(decoding: data.prefix(4_000_000), as: UTF8.self)
        return page(fromHTML: html, url: http.url ?? url)
    }

    /// Builds a page from raw HTML (the fast path).
    static func page(fromHTML html: String, url: URL) -> ProductPage {
        var page = ProductPage(url: url.absoluteString, title: decode(matches(#"<title[^>]*>([^<]*)</title>"#, in: html).first ?? ""))
        page.structured = matches(#"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html)
            .filter { block in
                guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { return false }
                return findProduct(json) != nil
            }
        for key in ["og:title", "og:description", "og:site_name", "og:image", "product:price:amount", "product:price:currency",
                    "og:price:amount", "og:price:currency"] {
            if let value = meta(key, in: html) { page.meta[key] = decode(value) }
        }
        if let h1 = matches(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html).first { page.meta["h1"] = decode(stripTags(h1)) }
        let body = matches(#"<body[^>]*>([\s\S]*)</body>"#, in: html).first ?? html
        page.text = String(stripTags(body.replacingOccurrences(of: #"<(script|style|noscript|svg)[\s\S]*?</\1>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s{2,}"#, with: "\n", options: .regularExpression).prefix(8000))
        let draft = parse(html: html, baseURL: url)
        page.imageURLs = [draft.imageURL].compactMap { $0 }
        return page
    }

    /// The biggest of the first two product photos that download (stores often list a small thumbnail first).
    private static func downloadImage(_ urls: [URL], referer: URL) async -> UIImage? {
        var seen = Set<String>()
        var found: [UIImage] = []
        for url in urls.prefix(6) where seen.insert(url.absoluteString).inserted {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            request.setValue("image/avif,image/webp,image/jpeg,image/png,*/*", forHTTPHeaderField: "Accept")
            if let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data),
               image.size.width >= 200, image.size.height >= 200 {
                found.append(image)
                if found.count == 2 || image.size.width * image.scale >= 1000 { break }
            }
        }
        return found.max { $0.size.width * $0.size.height * $0.scale * $0.scale < $1.size.width * $1.size.height * $1.scale * $1.scale }
    }

    /// What the page says without help from Gemini (used when ClosetWise can't be reached).
    /// The price from structured data or price meta tags only — exact, unlike a price label read off the page.
    static func structuredPrice(_ page: ProductPage) -> Decimal? {
        var copy = page
        copy.meta["price_text"] = nil
        return draft(from: copy).price
    }

    static func draft(from page: ProductPage) -> ProductDraft {
        var draft = ProductDraft()
        for block in page.structured {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
                  let product = findProduct(json) else { continue }
            draft = productDraft(product, base: URL(string: page.url))
            break
        }
        if draft.name.isEmpty { draft.name = page.meta["og:title"] ?? page.meta["h1"] ?? page.title }
        if draft.price == nil, let p = page.meta["product:price:amount"] ?? page.meta["og:price:amount"] { draft.price = Decimal(string: p) }
        if draft.price == nil, let text = page.meta["price_text"] { draft.price = price(in: text) }
        if draft.description == nil { draft.description = page.meta["og:description"] }
        draft.store = page.store
        return draft
    }

    /// The first amount in a price label like "$24.90" or "Now £18,00 Was £30,00".
    static func price(in text: String) -> Decimal? {
        guard let range = text.range(of: #"\d{1,5}(?:[.,]\d{3})*(?:[.,]\d{2})?"#, options: .regularExpression) else { return nil }
        var number = String(text[range])
        if number.range(of: #",\d{2}$"#, options: .regularExpression) != nil {   // 18,00 → 18.00
            number = number.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            number = number.replacingOccurrences(of: ",", with: "")
        }
        return Decimal(string: number).flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: Parsing (structured data and meta tags)

    static func parse(html: String, baseURL: URL?) -> ProductDraft {
        var draft = ProductDraft()
        for block in matches(#"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data),
                  let product = findProduct(json) else { continue }
            draft = productDraft(product, base: baseURL)
            break
        }
        if draft.name.isEmpty { draft.name = decode(meta("og:title", in: html) ?? matches(#"<title>([^<]*)</title>"#, in: html).first ?? "") }
        if draft.imageURL == nil, let img = meta("og:image", in: html) { draft.imageURL = URL(string: decode(img), relativeTo: baseURL) }
        if draft.price == nil, let p = meta("product:price:amount", in: html) ?? meta("og:price:amount", in: html) { draft.price = Decimal(string: p) }
        if draft.description == nil { draft.description = meta("og:description", in: html).map(decode) }
        draft.store = meta("og:site_name", in: html).map(decode)
        return draft
    }

    private static func productDraft(_ product: [String: Any], base: URL?) -> ProductDraft {
        var draft = ProductDraft()
        draft.name = decode((product["name"] as? String) ?? "")
        draft.description = product["description"] as? String
        draft.colorText = product["color"] as? String
        draft.material = product["material"] as? String
        if let brand = product["brand"] as? [String: Any] { draft.brand = brand["name"] as? String } else { draft.brand = product["brand"] as? String }
        draft.imageURL = imageURL(product["image"], base: base)
        var offers = (product["offers"] as? [String: Any]) ?? (product["offers"] as? [[String: Any]])?.first
        if offers == nil, let variants = product["hasVariant"] as? [[String: Any]] {
            offers = (variants.first?["offers"] as? [String: Any]) ?? (variants.first?["offers"] as? [[String: Any]])?.first
            if draft.imageURL == nil { draft.imageURL = imageURL(variants.first?["image"], base: base) }
        }
        if let p = offers?["price"] ?? offers?["lowPrice"] ?? (offers?["priceSpecification"] as? [String: Any])?["price"] {
            draft.price = Decimal(string: "\(p)")
        }
        return draft
    }

    static func findProduct(_ json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            let types = (dict["@type"] as? [String]) ?? [(dict["@type"] as? String) ?? ""]
            if types.contains(where: { $0 == "Product" || $0 == "ProductGroup" }) { return dict }
            if let graph = dict["@graph"] { return findProduct(graph) }
            if let main = dict["mainEntity"] { return findProduct(main) }
        }
        if let array = json as? [Any] { for element in array { if let p = findProduct(element) { return p } } }
        return nil
    }

    /// All image links in a schema.org `image` value (a string, an array, or ImageObjects).
    static func imageURLs(_ value: Any?, base: URL?) -> [URL] {
        if let s = value as? String { return [URL(string: s, relativeTo: base)].compactMap { $0 } }
        if let a = value as? [Any] { return a.flatMap { imageURLs($0, base: base) } }
        if let d = value as? [String: Any] { return imageURLs(d["url"] ?? d["contentUrl"], base: base) }
        return []
    }

    private static func imageURL(_ value: Any?, base: URL?) -> URL? {
        if let s = value as? String { return URL(string: s, relativeTo: base) }
        if let a = value as? [Any] { return imageURL(a.first, base: base) }
        if let d = value as? [String: Any] { return imageURL(d["url"] ?? d["contentUrl"], base: base) }
        return nil
    }

    private static func meta(_ key: String, in html: String) -> String? {
        matches(#"<meta[^>]+(?:property|name)=["']\#(key)["'][^>]*content=["']([^"']*)["']"#, in: html).first
            ?? matches(#"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(key)["']"#, in: html).first
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func stripTags(_ s: String) -> String {
        decode(s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
    }

    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&rsquo;", with: "’")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Hidden browser

/// Loads a page in an invisible WebKit view — the same engine as Safari — so pages built by JavaScript fill
/// in and many bot checks pass, then reads the product data out of the finished page.
/// Nothing is kept: a private, in-memory session is used and the view is removed afterwards.
@MainActor
final class WebPageReader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var loaded = false

    func read(_ url: URL, timeout: TimeInterval = 14) async -> ProductPage? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        // Behind the app's own views: never seen, but WebKit treats it as on screen and runs the page normally.
        if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            window.insertSubview(webView, at: 0)
        }
        self.webView = webView
        defer {
            webView.stopLoading()
            webView.removeFromSuperview()
            self.webView = nil
        }
        webView.load(URLRequest(url: url))

        // Poll the page as it builds. Stop once it shows a product with its price; after the page has
        // finished loading, wait a few more seconds for the price, then go with what's there.
        let deadline = Date.now.addingTimeInterval(timeout)
        var best: ProductPage?
        var loadedAt: Date?
        try? await Task.sleep(for: .milliseconds(1200))
        while Date.now < deadline {
            if loaded && loadedAt == nil { loadedAt = .now }
            if let page = await extract(from: webView) {
                if best == nil || page.hasProductSignals || !(best?.hasProductSignals ?? false) { best = page }
                if page.hasProductSignals && page.hasPrice { break }
                if page.hasProductSignals, let loadedAt, Date.now.timeIntervalSince(loadedAt) > 4 { break }
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        return best
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.loaded = true }
    }

    private static let script = """
    (() => {
      const q = s => document.querySelector(s);
      const meta = n => (q(`meta[property="${n}"]`) || q(`meta[name="${n}"]`))?.content || null;
      const ld = [...document.querySelectorAll('script[type="application/ld+json"]')].map(s => s.textContent || '');
      const images = [...document.images]
        .filter(i => i.naturalWidth >= 300 && i.naturalHeight >= 300)
        .map(i => { const r = i.getBoundingClientRect(); return { src: i.currentSrc || i.src, area: r.width * r.height, top: r.top + window.scrollY }; })
        .filter(i => i.src && i.src.startsWith('http') && i.area > 20000)
        .sort((a, b) => (a.top < 1500) === (b.top < 1500) ? b.area - a.area : (a.top < 1500 ? -1 : 1))
        .slice(0, 6).map(i => i.src);
      const keys = ['og:title','og:description','og:site_name','og:image','product:price:amount','product:price:currency','og:price:amount','og:price:currency'];
      const m = {}; keys.forEach(k => { const v = meta(k); if (v) m[k] = v; });
      const h1 = q('h1')?.innerText?.trim(); if (h1) m.h1 = h1;
      const money = /[$£€¥]\\s?\\d|\\d[.,]\\d{2}\\s?(€|kr|zł)/;
      const priceEl = [...document.querySelectorAll('[itemprop="price"], [class*="price" i], [data-testid*="price" i], [id*="price" i]')]
        .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.top + window.scrollY < 1600; })
        .map(e => (e.getAttribute('content') || e.innerText || '').trim())
        .find(t => t && t.length < 60 && money.test(t));
      if (priceEl) m.price_text = priceEl;
      return JSON.stringify({ url: location.href, title: document.title || '', ld, meta: m, images,
        text: (document.body?.innerText || '').replace(/\\n{2,}/g, '\\n').slice(0, 8000) });
    })()
    """

    private func extract(from webView: WKWebView) async -> ProductPage? {
        struct Raw: Decodable { let url: String; let title: String; let ld: [String]; let meta: [String: String]; let images: [String]; let text: String }
        guard let json = try? await webView.evaluateJavaScript(Self.script) as? String,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(json.utf8)) else { return nil }
        var page = ProductPage(url: raw.url, title: raw.title, meta: raw.meta, text: raw.text)
        page.via = "browser"
        page.structured = raw.ld.filter { block in
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { return false }
            return ProductLinkFetcher.findProduct(json) != nil
        }
        // Prefer the structured product image, then the biggest pictures near the top of the page.
        let structuredImage = ProductLinkFetcher.draft(from: page).imageURL
        page.imageURLs = ([structuredImage] + raw.images.map { URL(string: $0) }).compactMap { $0 }
        return page
    }
}
