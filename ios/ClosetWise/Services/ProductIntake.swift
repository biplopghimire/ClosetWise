import Foundation
import Supabase
import UIKit
import Vision
import CoreImage

/// What we could read about a product before the user confirms it.
struct ProductDraft {
    var name = ""
    var brand: String?
    var store: String?
    var price: Decimal?
    var colorText: String?
    var material: String?
    var description: String?
    var imageURL: URL?
    var image: UIImage?
}

// MARK: - Product links

/// Reads a product page on the device: schema.org Product JSON-LD first, then Open Graph tags.
enum ProductLinkFetcher {
    enum FetchError: LocalizedError {
        case badURL, blocked(Int), nothingFound
        var errorDescription: String? {
            switch self {
            case .badURL: "That doesn't look like a product link."
            case .blocked(let code): "The store didn't let us read that page (\(code)). Try a screenshot or photo instead."
            case .nothingFound: "Couldn't find product details on that page. Try a screenshot or photo instead."
            }
        }
    }

    static func fetch(_ text: String) async throws -> ProductDraft {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            throw FetchError.badURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw FetchError.blocked(http.statusCode) }
        let html = String(decoding: data, as: UTF8.self)

        var draft = parse(html: html, baseURL: url)
        draft.store = draft.store ?? url.host?.replacingOccurrences(of: "www.", with: "")
        guard !draft.name.isEmpty else { throw FetchError.nothingFound }
        if let imageURL = draft.imageURL, let (imageData, _) = try? await URLSession.shared.data(from: imageURL) {
            draft.image = UIImage(data: imageData)
        }
        return draft
    }

    static func parse(html: String, baseURL: URL?) -> ProductDraft {
        var draft = ProductDraft()

        // JSON-LD
        for block in matches(#"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html) {
            guard let data = block.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let product = findProduct(json) {
                draft.name = (product["name"] as? String) ?? draft.name
                draft.description = product["description"] as? String
                draft.colorText = product["color"] as? String
                draft.material = product["material"] as? String
                if let brand = product["brand"] as? [String: Any] { draft.brand = brand["name"] as? String }
                else { draft.brand = product["brand"] as? String }
                draft.imageURL = imageURL(product["image"], base: baseURL)
                let offers = (product["offers"] as? [String: Any]) ?? (product["offers"] as? [[String: Any]])?.first
                if let p = offers?["price"] ?? offers?["lowPrice"] { draft.price = Decimal(string: "\(p)") }
                break
            }
        }

        // Open Graph fallback
        func meta(_ key: String) -> String? {
            matches(#"<meta[^>]+(?:property|name)=["']\#(key)["'][^>]*content=["']([^"']*)["']"#, in: html).first
                ?? matches(#"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(key)["']"#, in: html).first
        }
        if draft.name.isEmpty { draft.name = decode(meta("og:title") ?? matches(#"<title>([^<]*)</title>"#, in: html).first ?? "") }
        if draft.imageURL == nil, let img = meta("og:image") { draft.imageURL = URL(string: img, relativeTo: baseURL) }
        if draft.price == nil, let p = meta("product:price:amount") ?? meta("og:price:amount") { draft.price = Decimal(string: p) }
        if draft.description == nil { draft.description = meta("og:description").map(decode) }
        draft.store = meta("og:site_name")
        return draft
    }

    private static func findProduct(_ json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            let type = dict["@type"]
            if (type as? String) == "Product" || (type as? [String])?.contains("Product") == true { return dict }
            if let graph = dict["@graph"] { return findProduct(graph) }
        }
        if let array = json as? [Any] { for element in array { if let p = findProduct(element) { return p } } }
        return nil
    }

    private static func imageURL(_ value: Any?, base: URL?) -> URL? {
        if let s = value as? String { return URL(string: s, relativeTo: base) }
        if let a = value as? [Any] { return imageURL(a.first, base: base) }
        if let d = value as? [String: Any] { return imageURL(d["url"] ?? d["contentUrl"], base: base) }
        return nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Attribute guessing (offline)

/// Best guess at attributes from product text, used when Gemini isn't connected.
/// The user always confirms on the next screen.
enum AttributeGuesser {
    static func guess(_ d: ProductDraft) -> WardrobeItem {
        let text = [d.name, d.description ?? "", d.colorText ?? "", d.material ?? ""].joined(separator: " ").lowercased()
        let kind = guessKind(text)
        let color = ColorMath.normalize(d.colorText ?? "") ?? ColorMath.normalize(text) ?? ("black", 0x1D1D1F)
        return WardrobeItem(
            name: d.name.isEmpty ? "New item" : String(d.name.prefix(60)),
            category: category(for: kind), kind: kind,
            color: color.name, hex: color.hex,
            material: d.material ?? guessMaterial(text) ?? "",
            fit: guessFit(text, kind: kind),
            silhouette: guessCut(text),
            style: guessStyle(text, kind: kind),
            formality: guessFormality(text, kind: kind),
            price: d.price,
            store: d.store
        )
    }

    static func category(for kind: GarmentKind) -> ItemCategory {
        switch kind {
        case .tee, .knit, .hoodie, .shirt: .top
        case .jacket, .coat: .outerwear
        case .trousers, .skirt, .shorts: .bottom
        case .shoes: .shoes
        }
    }

    /// A drawn shape for an item synced without one.
    static func defaultKind(for category: ItemCategory) -> GarmentKind {
        switch category {
        case .top: .tee
        case .outerwear: .jacket
        case .bottom: .trousers
        case .shoes: .shoes
        default: .shirt
        }
    }

    private static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.range(of: "\\b\($0)", options: .regularExpression) != nil }
    }

    static func guessKind(_ t: String) -> GarmentKind {
        if has(t, ["sneaker", "trainer", "loafer", "boot", "shoe", "sandal", "mule", "heel", "flat"]) { return .shoes }
        if has(t, ["coat", "trench", "parka", "overcoat", "puffer"]) { return .coat }
        if has(t, ["jacket", "blazer", "overshirt", "bomber", "shacket", "gilet"]) { return .jacket }
        if has(t, ["hoodie", "sweatshirt", "zip-up"]) { return .hoodie }
        if has(t, ["shorts"]) { return .shorts }
        if has(t, ["skirt"]) { return .skirt }
        if has(t, ["jean", "trouser", "pant", "chino", "legging", "jogger", "cargo"]) { return .trousers }
        if has(t, ["shirt", "blouse", "oxford", "button"]) && !has(t, ["t-shirt", "tshirt"]) { return .shirt }
        if has(t, ["sweater", "jumper", "cardigan", "knit", "pullover", "turtleneck", "long sleeve", "ribbed"]) { return .knit }
        return .tee
    }

    static func guessFit(_ t: String, kind: GarmentKind) -> FitType {
        if has(t, ["oversized", "boxy", "slouchy"]) { return .oversized }
        if has(t, ["baggy", "loose", "wide", "barrel", "balloon"]) { return .loose }
        if has(t, ["relaxed", "easy fit", "straight"]) { return .relaxed }
        if has(t, ["skinny", "bodycon", "second skin", "compression"]) { return .tight }
        if has(t, ["slim", "fitted", "tailored", "ribbed", "cropped fit"]) { return .fitted }
        return .regular
    }

    static func guessCut(_ t: String) -> String? {
        let cuts = ["wide-leg", "wide leg", "straight", "skinny", "bootcut", "flare", "barrel", "tapered", "cropped", "a-line",
                    "pleated", "midi", "mini", "maxi", "crew neck", "v-neck", "turtleneck", "boxy", "longline", "double-breasted",
                    "single-breasted", "button-down", "long sleeve", "tank", "low-top", "high-top", "penny loafer"]
        return cuts.first { t.contains($0) }.map { $0.replacingOccurrences(of: "wide leg", with: "wide-leg") }
    }

    static func guessMaterial(_ t: String) -> String? {
        ["cashmere", "merino", "wool", "linen", "silk", "leather", "suede", "denim", "corduroy", "fleece", "polyester", "nylon", "cotton", "canvas", "rib"]
            .first { t.contains($0) }
    }

    static func guessStyle(_ t: String, kind: GarmentKind) -> String {
        if has(t, ["tailored", "blazer", "suit", "wool trouser", "dress shirt"]) { return "smart" }
        if has(t, ["sport", "athletic", "running", "track", "gym"]) { return "sporty" }
        if kind == .hoodie { return "lounge" }
        if has(t, ["chore", "utility", "cargo", "workwear", "canvas"]) { return "workwear" }
        return "casual"
    }

    static func guessFormality(_ t: String, kind: GarmentKind) -> Int {
        if has(t, ["suit", "tuxedo", "gown"]) { return 5 }
        if has(t, ["blazer", "tailored", "dress shirt", "wool trouser"]) { return 4 }
        switch kind {
        case .hoodie, .shorts: return 1
        case .tee: return has(t, ["polo"]) ? 2 : 1
        case .shirt, .coat, .skirt: return 3
        default: return 2
        }
    }
}

// MARK: - Photos

enum GarmentPhoto {
    /// Lifts the garment off its background on device (Vision); returns nil when no subject is found.
    static func cutout(_ image: UIImage) async -> UIImage? {
        guard let cg = image.resized(maxSide: 1024).cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
                let ci = CIImage(cvPixelBuffer: buffer)
                guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
                return UIImage(cgImage: out)
            } catch {
                return nil
            }
        }.value
    }

    /// Asks Gemini (via the `gemini` Edge Function) to read the garment's attributes.
    /// Returns nil when Supabase isn't configured or the user isn't signed in.
    @MainActor
    static func geminiAttributes(_ image: UIImage) async -> WardrobeItem? {
        guard let client = SupabaseService.client, await Cloud.shared.ensureSession() != nil,
              let jpeg = image.resized(maxSide: 1024).jpegData(compressionQuality: 0.8) else { return nil }
        struct Request: Encodable { let action = "attributes"; let image_base64: String; let mime_type = "image/jpeg" }
        struct Attributes: Decodable {
            let name: String; let category: String; let color: String; let material: String; let fit: String
            let silhouette: String?; let style: String; let formality: Int
        }
        struct Response: Decodable { let attributes: Attributes }
        guard let response: Response = try? await client.functions.invoke(
            "gemini", options: FunctionInvokeOptions(body: Request(image_base64: jpeg.base64EncodedString()))
        ) else { return nil }
        let a = response.attributes
        let kind = AttributeGuesser.guessKind("\(a.name) \(a.category)")
        let color = ColorMath.normalize(a.color) ?? ("black", 0x1D1D1F)
        return WardrobeItem(name: a.name.capitalized, category: ItemCategory(rawValue: a.category) ?? AttributeGuesser.category(for: kind),
                            kind: kind, color: color.name, hex: color.hex, material: a.material,
                            fit: FitType(rawValue: a.fit) ?? .regular, silhouette: a.silhouette, style: a.style, formality: a.formality)
    }
}
