import Foundation

/// Sample closet and outfit history matching the wireframes. Replaced by Supabase data in Phase 1.
enum SampleData {
    /// Stable IDs so saved outfit logs keep pointing at the same sample items across launches.
    private static func sid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let blackTee = WardrobeItem(id: sid(1), name: "Black tee", category: .top, kind: .tee, color: "black", hex: 0x1D1D1F, material: "cotton", fit: .regular, silhouette: "crew neck", style: "casual", formality: 1, price: 20, wearCount: 24, daysSinceWorn: 1)
    static let whiteShirt = WardrobeItem(id: sid(2), name: "White shirt", category: .top, kind: .shirt, color: "white", hex: 0xF2F1EC, material: "cotton poplin", fit: .regular, silhouette: "button-down", style: "smart casual", formality: 3, price: 45, wearCount: 15, daysSinceWorn: 6)
    static let skyOxford = WardrobeItem(id: sid(3), name: "Sky oxford", category: .top, kind: .shirt, color: "blue", hex: 0xA3C9E2, material: "oxford cotton", fit: .relaxed, silhouette: "button-down", style: "smart casual", formality: 3, price: 60, wearCount: 4, daysSinceWorn: 41)
    static let knitSweater = WardrobeItem(id: sid(4), name: "Knit sweater", category: .top, kind: .knit, color: "cream", hex: 0xE8DFCB, material: "wool", fit: .relaxed, silhouette: "crew neck", style: "casual", formality: 2, price: 60, wearCount: 9, daysSinceWorn: 4)
    static let oliveKnit = WardrobeItem(id: sid(5), name: "Olive knit", category: .top, kind: .knit, color: "green", hex: 0x758151, material: "lambswool", fit: .regular, silhouette: "crew neck", style: "casual", formality: 2, price: 85, wearCount: 3, daysSinceWorn: 54)
    static let blackTop = WardrobeItem(id: sid(6), name: "Black top", category: .top, kind: .knit, color: "black", hex: 0x19191B, material: "cotton rib", fit: .fitted, silhouette: "long sleeve", style: "casual", formality: 2, price: 30, wearCount: 8, daysSinceWorn: 9)
    static let tank = WardrobeItem(id: sid(7), name: "Black tank", category: .top, kind: .tee, color: "black", hex: 0x232325, material: "cotton", fit: .tight, silhouette: "tank", style: "casual", formality: 1, price: 15, wearCount: 5, daysSinceWorn: 20)
    static let greyHoodie = WardrobeItem(id: sid(8), name: "Grey hoodie", category: .top, kind: .hoodie, color: "grey", hex: 0xA0A5AB, material: "fleece", fit: .oversized, silhouette: "pullover", style: "lounge", formality: 1, price: 55, wearCount: 18, daysSinceWorn: 2)
    static let blackBlazer = WardrobeItem(id: sid(9), name: "Black blazer", category: .outerwear, kind: .jacket, color: "black", hex: 0x232427, material: "wool", fit: .fitted, silhouette: "single-breasted", style: "smart", formality: 4, price: 150, wearCount: 3, daysSinceWorn: 72)
    static let trenchCoat = WardrobeItem(id: sid(10), name: "Trench coat", category: .outerwear, kind: .coat, color: "beige", hex: 0xC9A97C, material: "cotton gabardine", fit: .relaxed, silhouette: "belted, knee-length", style: "classic", formality: 3, price: 180, wearCount: 4, daysSinceWorn: 65)

    static let wideLegJeans = WardrobeItem(id: sid(11), name: "Wide-leg jeans", category: .bottom, kind: .trousers, color: "denim", hex: 0x5B7FA8, material: "denim", fit: .loose, silhouette: "wide-leg", style: "casual", formality: 2, price: 80, wearCount: 19, daysSinceWorn: 1)
    static let greyTrousers = WardrobeItem(id: sid(12), name: "Grey trousers", category: .bottom, kind: .trousers, color: "grey", hex: 0x8A8D90, material: "wool", fit: .regular, silhouette: "straight", style: "smart", formality: 4, price: 70, wearCount: 7, daysSinceWorn: 6)
    static let midiSkirt = WardrobeItem(id: sid(13), name: "Midi skirt", category: .bottom, kind: .skirt, color: "green", hex: 0x7FA58A, material: "polyester", fit: .relaxed, silhouette: "pleated A-line", style: "feminine", formality: 3, price: 55, wearCount: 6, daysSinceWorn: 33)
    static let denimShorts = WardrobeItem(id: sid(14), name: "Denim shorts", category: .bottom, kind: .shorts, color: "denim", hex: 0x9BB8D6, material: "denim", fit: .relaxed, silhouette: "mid-thigh", style: "casual", formality: 1, price: 35, wearCount: 6, daysSinceWorn: 80)

    static let loafers = WardrobeItem(id: sid(15), name: "Loafers", category: .shoes, kind: .shoes, color: "brown", hex: 0x7A4528, material: "leather", fit: .regular, silhouette: "penny loafer", style: "classic", formality: 3, price: 120, wearCount: 11, daysSinceWorn: 3)
    static let sneakers = WardrobeItem(id: sid(16), name: "White sneakers", category: .shoes, kind: .shoes, color: "white", hex: 0xF1F0EC, material: "leather", fit: .regular, silhouette: "low-top", style: "casual", formality: 1, price: 90, wearCount: 30, daysSinceWorn: 1)

    static let wardrobe: [WardrobeItem] = [
        blackTee, whiteShirt, skyOxford, knitSweater, oliveKnit, blackTop, tank, greyHoodie, blackBlazer, trenchCoat,
        wideLegJeans, greyTrousers, midiSkirt, denimShorts,
        loafers, sneakers,
    ]

    /// A few weeks of logged outfits so the style profile has something to learn from.
    static let outfitLogs: [OutfitLog] = {
        // Stable IDs too, so loading the demo twice (or on two phones) doesn't duplicate its outfits.
        func log(_ daysAgo: Int, _ pieces: [WardrobeItem], _ reaction: OutfitLog.Reaction? = nil) -> OutfitLog {
            OutfitLog(id: sid(100 + daysAgo), date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
                      itemIDs: pieces.map(\.id), reaction: reaction)
        }
        return [
            log(1, [blackTee, wideLegJeans, sneakers], .loved),
            log(2, [greyHoodie, wideLegJeans, sneakers]),
            log(3, [blackTee, wideLegJeans, loafers]),
            log(4, [knitSweater, wideLegJeans, loafers], .loved),
            log(6, [whiteShirt, greyTrousers, loafers]),
            log(9, [blackTop, wideLegJeans, sneakers], .loved),
            log(12, [knitSweater, greyTrousers, loafers]),
            log(15, [greyHoodie, wideLegJeans, sneakers]),
            log(20, [tank, wideLegJeans, sneakers], .fine),
            log(33, [whiteShirt, midiSkirt, loafers]),
            log(41, [skyOxford, greyTrousers, loafers], .fine),
        ]
    }()

    static let ribbedTop = WardrobeItem(id: sid(17), name: "Black ribbed top", category: .top, kind: .knit, color: "black", hex: 0x18181A, material: "cotton", fit: .fitted, silhouette: "long sleeve", style: "casual", formality: 2, price: 38)

    /// Products to try the purchase check with (no link needed).
    static let exampleProducts: [WardrobeItem] = [
        WardrobeItem(name: "Black ribbed top", category: .top, kind: .knit, color: "black", hex: 0x18181A, material: "cotton rib", fit: .fitted, silhouette: "long sleeve", style: "casual", formality: 2, price: 38, store: "store.com"),
        WardrobeItem(name: "Camel wide-leg trousers", category: .bottom, kind: .trousers, color: "beige", hex: 0xC4A27A, material: "wool blend", fit: .loose, silhouette: "wide-leg", style: "smart casual", formality: 3, price: 89, store: "store.com"),
        WardrobeItem(name: "Red skinny jeans", category: .bottom, kind: .trousers, color: "red", hex: 0xB33A3A, material: "stretch denim", fit: .tight, silhouette: "skinny", style: "casual", formality: 2, price: 59, store: "store.com"),
        WardrobeItem(name: "Navy chore jacket", category: .outerwear, kind: .jacket, color: "navy", hex: 0x26344F, material: "cotton canvas", fit: .relaxed, silhouette: "boxy", style: "workwear", formality: 2, price: 120, store: "store.com"),
    ]

    static let purchaseHistory: [PurchaseRecord] = [
        PurchaseRecord(id: sid(201), date: Calendar.current.date(byAdding: .day, value: -5, to: .now)!,
                       product: WardrobeItem(id: sid(18), name: "Linen shirt", category: .top, kind: .shirt, color: "cream", hex: 0xE9E1CF, material: "linen", fit: .relaxed, silhouette: "button-down", style: "casual", price: 45),
                       verdict: "Consider", styleScore: 62, similarCount: 1, outfitCount: 5, decision: .skipped),
        PurchaseRecord(id: sid(202), date: Calendar.current.date(byAdding: .day, value: -40, to: .now)!,
                       product: loafers, verdict: "Adds value", styleScore: 74, similarCount: 0, outfitCount: 14, decision: .bought),
    ]
}
