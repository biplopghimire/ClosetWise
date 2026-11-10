import SwiftUI

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case top, bottom, outerwear, dress, shoes, accessory
    var id: String { rawValue }

    var filterTitle: String {
        switch self {
        case .top: "Tops"
        case .bottom: "Bottoms"
        case .outerwear: "Coats"
        case .dress: "Dresses"
        case .shoes: "Shoes"
        case .accessory: "Accessories"
        }
    }
}

/// How a piece sits on the body, from tightest to roomiest.
/// Stored on every item and confirmed by the user on the Review screen.
enum FitType: String, Codable, CaseIterable, Identifiable {
    case tight, fitted, regular, relaxed, loose, oversized
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .tight: "Hugs the body"
        case .fitted: "Follows your shape"
        case .regular: "True to size"
        case .relaxed: "A little extra room"
        case .loose: "Roomy, drapes away"
        case .oversized: "Intentionally big"
        }
    }

    /// 0 (tight) … 5 (oversized)
    var ease: Int { FitType.allCases.firstIndex(of: self) ?? 2 }
}

/// Mirrors the `items` table.
struct WardrobeItem: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var category: ItemCategory
    var kind: GarmentKind
    var color: String
    var hex: UInt32
    var material: String
    var fit: FitType
    /// Cut or shape, e.g. "wide-leg", "straight", "cropped", "A-line".
    var silhouette: String?
    var style: String
    /// 1 = loungewear … 5 = formal
    var formality: Int
    var price: Decimal?
    var wearCount: Int
    var lastWorn: Date?
    /// Local photo file (cut-out when background removal succeeded); drawn artwork is used when nil.
    var photo: String?
    var store: String?
    /// When this phone last changed the item; sync keeps whichever copy is newer.
    var updatedAt: Date?

    init(id: UUID = UUID(), name: String, category: ItemCategory, kind: GarmentKind, color: String, hex: UInt32,
         material: String, fit: FitType, silhouette: String? = nil, style: String, formality: Int = 2,
         price: Decimal? = nil, wearCount: Int = 0, daysSinceWorn: Int? = nil, photo: String? = nil, store: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.color = color
        self.hex = hex
        self.material = material
        self.fit = fit
        self.silhouette = silhouette
        self.style = style
        self.formality = formality
        self.price = price
        self.wearCount = wearCount
        self.photo = photo
        self.store = store
        self.lastWorn = daysSinceWorn.map { Calendar.current.date(byAdding: .day, value: -$0, to: .now)! }
    }

    var swatch: Color { Color(hex: hex) }

    var daysSinceWorn: Int? {
        lastWorn.map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 }
    }

    var costPerWear: Decimal? {
        guard let price, wearCount > 0 else { return nil }
        return price / Decimal(wearCount)
    }

    /// "Relaxed · wide-leg"
    var fitDescription: String {
        [fit.label, silhouette].compactMap { $0 }.joined(separator: " · ")
    }

    static let neutralColors: Set<String> = ["black", "white", "grey", "gray", "beige", "cream", "navy", "denim", "brown", "camel", "tan", "ivory"]
    var isNeutral: Bool { Self.neutralColors.contains(color.lowercased()) }
}

/// A finished purchase check (mirrors `purchase_checks`).
struct PurchaseRecord: Identifiable, Codable, Hashable {
    enum Decision: String, Codable { case bought = "Bought", skipped = "Skipped" }

    var id = UUID()
    var date = Date.now
    var product: WardrobeItem
    var verdict: String
    var styleScore: Int
    var similarCount: Int
    var outfitCount: Int
    var decision: Decision?
}

extension Decimal {
    var dollars: String {
        let n = NSDecimalNumber(decimal: self).doubleValue
        return n.rounded() == n ? "$\(Int(n))" : String(format: "$%.2f", n)
    }
}
