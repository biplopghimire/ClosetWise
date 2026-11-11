import Foundation
import os
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
        // A polo sweatshirt has a collar, not a hood.
        if has(t, ["polo"]) && has(t, ["sweatshirt", "fleece", "sweater", "knit"]) { return .knit }
        if has(t, ["sweatpant", "trackpant", "track pant", "jogger", "slacks"]) { return .trousers }
        if has(t, ["hoodie", "sweatshirt", "zip-up"]) { return .hoodie }
        if has(t, ["shorts"]) { return .shorts }
        if has(t, ["skirt"]) { return .skirt }
        if has(t, ["jean", "trouser", "pant", "chino", "legging", "jogger", "cargo", "bottom"]) { return .trousers }
        if has(t, ["polo"]) { return .shirt }
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
        struct Response: Decodable { let attributes: GeminiAttributes }
        guard let response: Response = try? await client.functions.invoke(
            "gemini", options: SupabaseService.geminiOptions(body: Request(image_base64: jpeg.base64EncodedString()))
        ) else { return nil }
        return response.attributes.item
    }

    /// What ClosetWise made of a product page: the item, plus what only the listing knows.
    struct ProductReading {
        var isProduct: Bool
        var item: WardrobeItem
        var brand: String?
        var price: Decimal?
    }

    /// Sends what the phone read off a product page (and its photo) to ClosetWise to read like a shopper would.
    static func geminiProduct(_ page: ProductPage, image: UIImage?) async -> ProductReading? {
        guard let client = SupabaseService.client, await Cloud.shared.ensureSession() != nil else { return nil }
        struct Request: Encodable { let action = "read_product"; let page: ProductPage; let image_base64: String?; let mime_type = "image/jpeg" }
        struct Product: Decodable {
            let is_product: Bool; let brand: String?; let price: Double?; let currency: String?
            let attributes: GeminiAttributes
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                is_product = try c.decodeIfPresent(Bool.self, forKey: .is_product) ?? true
                brand = try c.decodeIfPresent(String.self, forKey: .brand)
                price = try c.decodeIfPresent(Double.self, forKey: .price)
                currency = try c.decodeIfPresent(String.self, forKey: .currency)
                attributes = try GeminiAttributes(from: decoder)
            }
            enum Keys: String, CodingKey { case is_product, brand, price, currency }
        }
        struct Response: Decodable { let product: Product }
        let jpeg = image?.resized(maxSide: 1024).jpegData(compressionQuality: 0.8)?.base64EncodedString()
        let response: Response
        do {
            response = try await client.functions.invoke("gemini", options: SupabaseService.geminiOptions(body: Request(page: page, image_base64: jpeg)))
        } catch {
            var detail = String(describing: error)
            if case let FunctionsError.httpError(code, data) = error { detail = "\(code): \(String(decoding: data, as: UTF8.self))" }
            Logger(subsystem: "app.closetwise", category: "links").error("read_product failed: \(detail, privacy: .public)")
            return nil
        }
        let p = response.product
        let brand = p.brand.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return ProductReading(isProduct: p.is_product, item: p.attributes.item, brand: brand,
                              price: p.price.flatMap { $0 > 0 ? Decimal(string: String(format: "%.2f", $0)) : nil })
    }
}

/// Item fields as ClosetWise (Gemini) returns them.
struct GeminiAttributes: Decodable {
    let name: String; let category: String; let color: String; let material: String; let fit: String
    let silhouette: String?; let style: String; let formality: Int
    let subcategory: String?

    var item: WardrobeItem {
        // The type guesser matches lowercase words; subcategory ("polo shirt", "chinos") is the strongest hint.
        let kind = AttributeGuesser.guessKind("\(subcategory ?? "") \(name) \(category) \(silhouette ?? "")".lowercased())
        let color = ColorMath.normalize(self.color) ?? ("black", 0x1D1D1F)
        return WardrobeItem(name: name.prefix(1).uppercased() + name.dropFirst(), category: ItemCategory(rawValue: category) ?? AttributeGuesser.category(for: kind),
                            kind: kind, color: color.name, hex: color.hex, material: material,
                            fit: FitType(rawValue: fit) ?? .regular, silhouette: silhouette, style: style,
                            formality: min(5, max(1, formality)))
    }

}
