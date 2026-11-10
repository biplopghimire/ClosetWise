import Foundation

/// One logged outfit (mirrors `outfits` + `wear_events`).
struct OutfitLog: Identifiable, Codable, Hashable {
    enum Reaction: String, Codable, CaseIterable { case loved, fine, notMe = "not_me" }
    enum Source: String, Codable { case logged, suggested }

    var id = UUID()
    var date: Date
    var itemIDs: [UUID]
    var reaction: Reaction?
    var source: Source = .logged
    /// Local photo file of the outfit, if one was taken.
    var photo: String?
    /// When this outfit last changed (sync keeps the newer copy).
    var updatedAt: Date?
}

/// What the user tells us about their style (mirrors `style_profiles.preferences`).
struct StylePreferences: Codable, Equatable {
    var vibes: [String] = []
    var about: String = ""
    /// Preferred fit per category, keyed by `ItemCategory.rawValue`.
    var fits: [String: FitType] = [:]
    var loveColors: [String] = []
    var avoidColors: [String] = []
    /// 1 lounge … 5 formal; nil = learn it from outfits.
    var dressiness: Int?
    var occasions: [String] = []
    /// Local file names of inspiration photos (uploaded to the `inspiration` bucket once signed in).
    var inspirationFiles: [String] = []

    static let vibeOptions = ["Minimal", "Classic", "Streetwear", "Preppy", "Boho", "Romantic", "Edgy", "Sporty",
                              "Vintage", "Y2K", "Scandi", "Workwear", "Quiet luxury", "Coastal", "Grunge", "Smart casual"]
    static let occasionOptions = ["Class", "Office", "Weekend", "Going out", "Dates", "Gym", "Travel", "Events"]
    static let palette: [(name: String, hex: UInt32)] = [
        ("black", 0x1D1D1F), ("white", 0xF4F3EF), ("grey", 0x9A9EA3), ("cream", 0xE8DFCB), ("beige", 0xC9A97C),
        ("brown", 0x7A4528), ("navy", 0x23324F), ("denim", 0x5B7FA8), ("blue", 0x8DB7DA), ("green", 0x6E9E7F),
        ("olive", 0x758151), ("red", 0xB33A3A), ("pink", 0xE3A6B8), ("purple", 0x8E79B5), ("yellow", 0xE6C65C), ("orange", 0xDE8B3C),
    ]
    static let dressinessLabels = ["Lounge", "Casual", "Smart casual", "Dressy", "Formal"]
}

struct Weighted<T: Hashable>: Hashable {
    let value: T
    let share: Double
}

/// What we've learned from the outfits a user actually wears.
struct LearnedStyle {
    var outfitCount = 0
    var colors: [Weighted<String>] = []
    var fits: [ItemCategory: [Weighted<FitType>]] = [:]
    var silhouettes: [ItemCategory: [Weighted<String>]] = [:]
    var styles: [Weighted<String>] = []
    var formality: Double = 2
    var signaturePieces: [WardrobeItem] = []
    var lovedPairs: Set<String> = []
    var tags: [String] = []
    var summary = ""

    var neutralShare: Double {
        colors.filter { WardrobeItem.neutralColors.contains($0.value) }.map(\.share).reduce(0, +)
    }

    /// How often the user wears this item's fit, within its category (0…1).
    func fitShare(_ item: WardrobeItem) -> Double {
        fits[item.category]?.first { $0.value == item.fit }?.share ?? 0
    }

    func topFit(_ category: ItemCategory) -> Weighted<FitType>? { fits[category]?.first }

    static func pairKey(_ a: UUID, _ b: UUID) -> String { [a.uuidString, b.uuidString].sorted().joined(separator: "|") }
}

enum StyleLearner {
    /// Recent and loved outfits count more. Half-life of 30 days.
    static func weight(_ log: OutfitLog, now: Date = .now) -> Double {
        let days = max(0, now.timeIntervalSince(log.date) / 86_400)
        let recency = pow(0.5, days / 30)
        switch log.reaction {
        case .loved: return recency * 1.6
        case .notMe: return recency * 0.3
        default: return recency
        }
    }

    static func learn(items: [WardrobeItem], logs: [OutfitLog]) -> LearnedStyle {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let worn = logs.filter { $0.source == .logged || $0.reaction != .notMe }
        var style = LearnedStyle(outfitCount: worn.count)
        guard !worn.isEmpty else {
            style.summary = "Log a few outfits and we'll start to learn what you like to wear."
            return style
        }

        var colors: [String: Double] = [:]
        var fits: [ItemCategory: [FitType: Double]] = [:]
        var silhouettes: [ItemCategory: [String: Double]] = [:]
        var styles: [String: Double] = [:]
        var pieces: [UUID: Double] = [:]
        var formalitySum = 0.0, formalityWeight = 0.0

        for log in worn {
            let w = weight(log)
            let outfit = log.itemIDs.compactMap { byID[$0] }
            for item in outfit {
                colors[item.color.lowercased(), default: 0] += w
                fits[item.category, default: [:]][item.fit, default: 0] += w
                if let s = item.silhouette { silhouettes[item.category, default: [:]][s, default: 0] += w }
                styles[item.style, default: 0] += w
                pieces[item.id, default: 0] += w
                formalitySum += Double(item.formality) * w
                formalityWeight += w
            }
            if log.reaction == .loved {
                let tops = outfit.filter { $0.category == .top }, bottoms = outfit.filter { $0.category == .bottom }
                for t in tops { for b in bottoms { style.lovedPairs.insert(LearnedStyle.pairKey(t.id, b.id)) } }
            }
        }

        style.colors = normalized(colors)
        style.fits = fits.mapValues(normalized)
        style.silhouettes = silhouettes.mapValues(normalized)
        style.styles = normalized(styles)
        style.formality = formalityWeight > 0 ? formalitySum / formalityWeight : 2
        style.signaturePieces = pieces.sorted { $0.value > $1.value }.prefix(3).compactMap { byID[$0.key] }
        style.tags = tags(for: style)
        style.summary = summary(for: style)
        return style
    }

    private static func normalized<T: Hashable>(_ counts: [T: Double]) -> [Weighted<T>] {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts.map { Weighted(value: $0.key, share: $0.value / total) }.sorted { $0.share > $1.share }
    }

    private static func formalityLabel(_ f: Double) -> String {
        switch f {
        case ..<1.8: "Casual"
        case ..<2.6: "Everyday casual"
        case ..<3.4: "Smart casual"
        default: "Polished"
        }
    }

    private static func tags(for s: LearnedStyle) -> [String] {
        var tags: [String] = []
        if s.neutralShare >= 0.6 { tags.append("Neutrals") }
        if let accent = s.colors.first(where: { !WardrobeItem.neutralColors.contains($0.value) && $0.share >= 0.12 }) {
            tags.append("\(accent.value.capitalized) accents")
        }
        if let cut = s.silhouettes[.bottom]?.first, cut.share >= 0.4 { tags.append(sentenceCase(cut.value)) }
        if let topFit = s.topFit(.top), topFit.share >= 0.4 {
            switch topFit.value {
            case .oversized, .loose: tags.append("Oversized tops")
            case .relaxed: tags.append("Relaxed tops")
            case .fitted, .tight: tags.append("Fitted tops")
            case .regular: break
            }
        }
        let allFits = s.fits.values.flatMap { $0 }
        let ease = allFits.map { Double($0.value.ease) * $0.share }.reduce(0, +) / Double(max(1, s.fits.count))
        if ease >= 3.2 { tags.append("Relaxed fits") } else if ease <= 1.6 { tags.append("Fitted silhouettes") }
        tags.append(formalityLabel(s.formality))
        if let st = s.styles.first, !tags.contains(where: { $0.lowercased().contains(st.value.lowercased()) }) {
            tags.append(sentenceCase(st.value))
        }
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }.prefix(6).map { $0 }
    }

    /// "wide-leg" → "Wide-leg"
    private static func sentenceCase(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func summary(for s: LearnedStyle) -> String {
        var parts: [String] = []
        parts.append(s.neutralShare >= 0.6 ? "You mostly wear neutrals" : "You mix neutrals with colour")
        if let top = s.topFit(.top), let bottomCut = s.silhouettes[.bottom]?.first {
            parts[0] += ", usually \(top.value.rawValue) tops with \(bottomCut.value) bottoms"
        }
        var text = parts.joined() + "."
        text += " Your outfits land \(formalityLabel(s.formality).lowercased())"
        if let fav = s.signaturePieces.first { text += ", and you reach for your \(fav.name.lowercased()) most" }
        return text + "."
    }
}

/// Style context sent to Gemini (purchase checks, outfit judgment, style summary).
struct StyleContext: Encodable {
    struct Fit: Encodable { let category: String; let fit: String; let share: Double }
    let stated: StatedStyle
    let learned: Learned

    struct StatedStyle: Encodable {
        let vibes: [String]
        let in_their_words: String
        let preferred_fits: [String: String]
        let love_colors: [String]
        let avoid_colors: [String]
        let dressiness: String?
        let occasions: [String]
    }

    struct Learned: Encodable {
        let outfits_logged: Int
        let colors: [String: Double]
        let fits: [Fit]
        let silhouettes: [String: String]
        let typical_dressiness: Double
        let signature_pieces: [String]
        let tags: [String]
    }

    init(preferences p: StylePreferences, learned l: LearnedStyle) {
        func round(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        stated = StatedStyle(
            vibes: p.vibes, in_their_words: p.about,
            preferred_fits: p.fits.mapValues(\.rawValue),
            love_colors: p.loveColors, avoid_colors: p.avoidColors,
            dressiness: p.dressiness.map { StylePreferences.dressinessLabels[$0 - 1] },
            occasions: p.occasions
        )
        learned = Learned(
            outfits_logged: l.outfitCount,
            colors: Dictionary(uniqueKeysWithValues: l.colors.prefix(6).map { ($0.value, round($0.share)) }),
            fits: l.fits.flatMap { cat, fits in fits.prefix(2).map { Fit(category: cat.rawValue, fit: $0.value.rawValue, share: round($0.share)) } },
            silhouettes: l.silhouettes.compactMapValues { $0.first?.value }.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            typical_dressiness: round(l.formality),
            signature_pieces: l.signaturePieces.map { "\($0.name) (\($0.fitDescription))" },
            tags: l.tags
        )
    }
}

/// Gemini's written read of the user's style (mirrors `style_profiles.summary/tags`).
struct GeminiStyleSummary: Codable, Equatable {
    var summary: String
    var tags: [String]
    var fitNotes: String
    var updatedAt: Date
}
