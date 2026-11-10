import Foundation

struct Outfit: Identifiable, Hashable {
    var id: String { Outfit.comboKey(pieces.map(\.id)) }
    var top: WardrobeItem
    var bottom: WardrobeItem
    var shoes: WardrobeItem
    var layer: WardrobeItem?
    var title: String
    var reason: String
    var score: Double
    /// How well the pieces suit the user's style, 0…100.
    var styleScore: Int = 60

    var pieces: [WardrobeItem] { [layer, top, bottom, shoes].compactMap { $0 } }
    func contains(_ item: WardrobeItem) -> Bool { pieces.contains { $0.id == item.id } }

    static func comboKey(_ ids: [UUID]) -> String { ids.map(\.uuidString).sorted().joined(separator: "|") }
}

/// What the engine knows about the user's taste.
struct StyleSignals {
    var preferences = StylePreferences()
    var learned = LearnedStyle()
    var disliked: Set<String> = []
    var loved: Set<String> = []
    /// Today's weather, when the user shared their location.
    var weather: WeatherNow?
}

/// Rule-based outfit suggestions from what the user already owns, shaped by their style
/// (what they say they like and what they actually wear) and today's weather. Favors pieces
/// that haven't been worn lately.
enum OutfitEngine {
    /// How many pieces per category one round combines. Small closets fit entirely; big ones are
    /// sampled (best-suited pieces plus some randomness), and the feed draws a new sample when it runs out.
    struct Caps { var tops = 14, bottoms = 9, shoes = 6, layers = 4 }

    struct Ranking {
        var outfits: [Outfit]
        /// True when every piece was considered (nothing left out by the caps).
        var complete: Bool
    }

    /// Outfits the closet can make that suit the user and today's weather, best first.
    /// Each top + bottom + shoes appears plain and with up to two layers.
    /// `recentlyShown` sinks outfits the user saw in the last few days, so ideas stay fresh;
    /// `seed` varies which pieces a big closet's round uses (nil = the best-suited ones).
    static func rank(from items: [WardrobeItem], signals: StyleSignals = .init(), recentlyShown: [String: Date] = [:],
                     seed: UInt64? = nil, caps: Caps = .init()) -> [Outfit] {
        ranking(from: items, signals: signals, recentlyShown: recentlyShown, seed: seed, caps: caps).outfits
    }

    static func ranking(from items: [WardrobeItem], signals: StyleSignals = .init(), recentlyShown: [String: Date] = [:],
                        seed: UInt64? = nil, caps: Caps = .init()) -> Ranking {
        let style = Dictionary(items.map { ($0.id, PurchaseCheckEngine.styleFit($0, signals: signals)) }, uniquingKeysWith: { a, _ in a })
        var rng = SplitMix64(seed: seed ?? 0)

        // Pieces the weather allows, best-suited first (with a shuffle when sampling).
        func pick(_ category: ItemCategory, _ cap: Int) -> (items: [WardrobeItem], all: Bool) {
            let pool = items.filter { item in
                item.category == category && (signals.weather.map { Warmth.wearable(item, $0) } ?? true)
            }
            guard pool.count > cap else { return (pool, true) }
            let ranked = pool.map { item -> (WardrobeItem, Double) in
                var p = Double(style[item.id]?.score ?? 60) / 10
                let idle = item.daysSinceWorn ?? 0
                p += idle >= 60 ? 1.2 : idle >= 30 ? 0.7 : 0
                if seed != nil { p += Double(rng.next() % 1000) / 1000 * 4 }
                return (item, p)
            }
            return (ranked.sorted { $0.1 > $1.1 }.prefix(cap).map(\.0), false)
        }
        let tops = pick(.top, caps.tops), bottoms = pick(.bottom, caps.bottoms)
        let shoes = pick(.shoes, caps.shoes), layers = pick(.outerwear, caps.layers)
        let freshCutoff = Date.now.addingTimeInterval(-3 * 86_400)

        var kept: [(pieces: [WardrobeItem], layer: WardrobeItem?, score: Double)] = []
        for top in tops.items {
            for bottom in bottoms.items {
                for shoe in shoes.items {
                    var plain: (pieces: [WardrobeItem], layer: WardrobeItem?, score: Double)?
                    var layered: [(pieces: [WardrobeItem], layer: WardrobeItem?, score: Double)] = []
                    for layer in [WardrobeItem?.none] + layers.items.map(Optional.some) {
                        let pieces = layer.map { [$0, top, bottom, shoe] } ?? [top, bottom, shoe]
                        guard var score = score(pieces, layer: layer, signals: signals, style: style) else { continue }
                        if let seen = recentlyShown[Outfit.comboKey(pieces.map(\.id))], seen > freshCutoff { score -= 1.2 }
                        if layer == nil { plain = (pieces, nil, score) } else { layered.append((pieces, layer, score)) }
                    }
                    if let plain { kept.append(plain) }
                    kept += layered.sorted { $0.score > $1.score }.prefix(2)
                }
            }
        }

        let outfits = kept.filter { $0.score > -6 }.sorted { $0.score > $1.score }.map { k in
            describe(k.pieces, layer: k.layer, score: k.score, signals: signals, style: style)
        }
        return Ranking(outfits: outfits, complete: tops.all && bottoms.all && shoes.all && layers.all)
    }

    static func suggest(from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 6) -> [Outfit] {
        // Greedy pick, keeping suggestions varied.
        var picked: [Outfit] = []
        var uses: [UUID: Int] = [:]
        for outfit in rank(from: items, signals: signals) {
            if picked.contains(where: { Set($0.pieces.map(\.id)).intersection(outfit.pieces.map(\.id)).count >= 2 }) { continue }
            if outfit.pieces.contains(where: { (uses[$0.id] ?? 0) >= 2 }) { continue }
            picked.append(outfit)
            outfit.pieces.forEach { uses[$0.id, default: 0] += 1 }
            if picked.count == limit { break }
        }
        return picked
    }

    static func outfits(with item: WardrobeItem, from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 3) -> [Outfit] {
        Array(suggest(from: items, signals: signals, limit: 40).filter { $0.contains(item) }.prefix(limit))
    }

    /// Scores one combination (taste + style + weather); nil when the weather rules it out.
    private static func score(_ pieces: [WardrobeItem], layer: WardrobeItem?, signals: StyleSignals,
                              style: [UUID: PurchaseCheckResult.StyleFit]) -> Double? {
        var total = score(pieces, signals)
        // Style: how well each piece suits the user (same judgment as the purchase check), 0…100.
        let styleScore = pieces.reduce(0.0) { $0 + Double(style[$1.id]?.score ?? 60) } / Double(pieces.count)
        total += (styleScore - 60) / 10 * 0.9
        if let weather = signals.weather {
            let fit = Warmth.fit(pieces, weather)
            if fit.blocked { return nil }
            total += fit.score
        } else if layer != nil {
            total += 0.3   // a layer makes it feel finished
        }
        return total
    }

    /// Title and reason, written only for outfits that made the cut.
    private static func describe(_ pieces: [WardrobeItem], layer: WardrobeItem?, score: Double, signals: StyleSignals,
                                 style: [UUID: PurchaseCheckResult.StyleFit]) -> Outfit {
        let fits = pieces.compactMap { style[$0.id] }
        let styleScore = fits.isEmpty ? 60 : Double(fits.map(\.score).reduce(0, +)) / Double(fits.count)
        let weatherNote = signals.weather.flatMap { Warmth.note(pieces, $0) }
        let reasons = reasons(for: pieces, signals, styleFits: fits, styleScore: styleScore, weatherNote: weatherNote)
        let key = Outfit.comboKey(pieces.map(\.id))
        // Rotate among the three strongest reasons so a feed of ideas doesn't repeat itself.
        let pick = reasons.count > 1 && !signals.loved.contains(key) ? key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % min(3, reasons.count) : 0
        let byCategory = Dictionary(pieces.map { ($0.category, $0) }, uniquingKeysWith: { a, _ in a })
        return Outfit(top: byCategory[.top]!, bottom: byCategory[.bottom]!, shoes: byCategory[.shoes]!, layer: layer,
                      title: title(for: pieces, signals.weather), reason: reasons[pick], score: score,
                      styleScore: Int(styleScore.rounded()))
    }

    // MARK: Scoring

    private static func score(_ pieces: [WardrobeItem], _ signals: StyleSignals) -> Double {
        let key = Outfit.comboKey(pieces.map(\.id))
        if signals.disliked.contains(key) { return -10 }

        let formality = pieces.map(\.formality)
        let spread = Double((formality.max() ?? 0) - (formality.min() ?? 0))
        var s = -max(0, spread - 1) * 1.5

        let accents = pieces.filter { !$0.isNeutral }
        s -= Double(max(0, accents.count - 1)) * 2
        if accents.count == 1 { s += 0.4 }

        if let top = pieces.first(where: { $0.category == .top }), let bottom = pieces.first(where: { $0.category == .bottom }) {
            if top.color == bottom.color && !top.isNeutral { s -= 1 }
            if signals.learned.lovedPairs.contains(LearnedStyle.pairKey(top.id, bottom.id)) { s += 0.6 }
        }
        if signals.loved.contains(key) { s += 1 }

        // Style: dress the way they dress (or say they want to).
        let prefs = signals.preferences
        let avg = Double(formality.reduce(0, +)) / Double(max(1, formality.count))
        let target = prefs.dressiness.map(Double.init) ?? signals.learned.formality
        s -= abs(avg - target) * 0.6

        for piece in pieces {
            s += signals.learned.fitShare(piece) * 0.8
            if let wanted = prefs.fits[piece.category.rawValue] {
                let gap = abs(wanted.ease - piece.fit.ease)
                s += gap == 0 ? 0.8 : gap >= 2 ? -0.6 : 0
            }
            let color = piece.color.lowercased()
            if prefs.loveColors.contains(color) { s += 0.5 }
            if prefs.avoidColors.contains(color) { s -= 2 }

            // Get unworn pieces back into rotation.
            let idle = piece.daysSinceWorn ?? 0
            if idle >= 60 { s += 1.2 } else if idle >= 30 { s += 0.7 }
            if piece.wearCount <= 4 { s += 0.3 }
        }
        return s
    }

    private static func title(for pieces: [WardrobeItem], _ weather: WeatherNow?) -> String {
        let avg = Double(pieces.map(\.formality).reduce(0, +)) / Double(pieces.count)
        let base: String
        switch avg {
        case ..<1.6: base = "Easy weekend"
        case ..<2.4: base = "Everyday casual"
        case ..<3.2: base = "Smart casual"
        default: base = "Polished"
        }
        guard let weather else { return base }
        let layered = pieces.contains { $0.category == .outerwear }
        switch weather.band {
        case .cold, .freezing: return layered ? "Bundled-up \(base.lowercased())" : base
        case .hot: return "Hot-day \(base.lowercased())"
        default: return weather.isRainy && layered ? "Rainy-day \(base.lowercased())" : base
        }
    }

    /// Reasons this outfit works, strongest first.
    private static func reasons(for pieces: [WardrobeItem], _ signals: StyleSignals, styleFits: [PurchaseCheckResult.StyleFit],
                                styleScore: Double, weatherNote: String?) -> [String] {
        if signals.loved.contains(Outfit.comboKey(pieces.map(\.id))) { return ["A look you loved — worth repeating"] }
        var out: [String] = []
        if let weatherNote { out.append(weatherNote) }

        // Style, in the user's own terms.
        let vibe = styleFits.flatMap(\.reasons).first { $0.positive && $0.text.hasPrefix("Fits your") }
        if let vibe, styleScore >= 62 { out.append(vibe.text) }
        else if styleScore >= 78 { out.append("Very you — \(signals.learned.tags.prefix(2).joined(separator: ", ").lowercased().ifEmpty("your usual style"))") }

        if let idle = pieces.filter({ ($0.daysSinceWorn ?? 0) >= 30 }).max(by: { ($0.daysSinceWorn ?? 0) < ($1.daysSinceWorn ?? 0) }) {
            out.append("Gets your \(idle.name.lowercased()) out again — unworn \(idle.daysSinceWorn ?? 0) days")
        }
        if let top = pieces.first(where: { $0.category == .top }), let bottom = pieces.first(where: { $0.category == .bottom }),
           signals.learned.fitShare(top) >= 0.3, signals.learned.fitShare(bottom) >= 0.3 {
            out.append("Your usual mix: \(top.fit.rawValue) top, \(bottom.silhouette ?? bottom.fit.rawValue) bottoms")
        }
        if let accent = pieces.first(where: { !$0.isNeutral }) { out.append("\(accent.name) as the one pop of colour") }
        if out.isEmpty { out.append("All neutrals, nothing to overthink") }
        return out
    }
}

/// Small seedable random generator, so a sampled round of outfits can be reproduced.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
