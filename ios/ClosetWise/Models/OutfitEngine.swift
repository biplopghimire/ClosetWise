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
}

/// Rule-based outfit suggestions from what the user already owns, shaped by their
/// style profile (stated preferences + what they actually wear). Favors pieces that
/// haven't been worn lately. Phase 2 adds the backend's Gemini compatibility judgment.
enum OutfitEngine {
    static func suggest(from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 6) -> [Outfit] {
        let tops = items.filter { $0.category == .top }
        let bottoms = items.filter { $0.category == .bottom }
        let shoes = items.filter { $0.category == .shoes }
        let layers = items.filter { $0.category == .outerwear }

        var candidates: [Outfit] = []
        for top in tops {
            for bottom in bottoms {
                for shoe in shoes {
                    let base = [top, bottom, shoe]
                    var best = (pieces: base, layer: WardrobeItem?.none, score: score(base, signals))
                    for layer in layers {
                        let withLayer = [layer] + base
                        let s = score(withLayer, signals) + 0.3   // a layer makes it feel finished
                        if s > best.score { best = (withLayer, layer, s) }
                    }
                    guard best.score > -1.5 else { continue }
                    candidates.append(Outfit(top: top, bottom: bottom, shoes: shoe, layer: best.layer,
                                             title: title(for: best.pieces), reason: reason(for: best.pieces, signals),
                                             score: best.score))
                }
            }
        }

        // Greedy pick, keeping suggestions varied.
        var picked: [Outfit] = []
        var uses: [UUID: Int] = [:]
        for outfit in candidates.sorted(by: { $0.score > $1.score }) {
            if picked.contains(where: { Set($0.pieces.map(\.id)).intersection(outfit.pieces.map(\.id)).count >= 2 }) { continue }
            if outfit.pieces.contains(where: { (uses[$0.id] ?? 0) >= 2 }) { continue }
            picked.append(outfit)
            outfit.pieces.forEach { uses[$0.id, default: 0] += 1 }
            if picked.count == limit { break }
        }
        return picked
    }

    static func outfits(with item: WardrobeItem, from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 3) -> [Outfit] {
        let all = suggest(from: items, signals: signals, limit: 40)
        return Array(all.filter { $0.contains(item) }.prefix(limit))
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

    private static func title(for pieces: [WardrobeItem]) -> String {
        let avg = Double(pieces.map(\.formality).reduce(0, +)) / Double(pieces.count)
        switch avg {
        case ..<1.6: return "Easy weekend"
        case ..<2.4: return "Everyday casual"
        case ..<3.2: return "Smart casual"
        default: return "Polished"
        }
    }

    private static func reason(for pieces: [WardrobeItem], _ signals: StyleSignals) -> String {
        if signals.loved.contains(Outfit.comboKey(pieces.map(\.id))) { return "A look you loved — worth repeating" }
        if let idle = pieces.filter({ ($0.daysSinceWorn ?? 0) >= 30 }).max(by: { ($0.daysSinceWorn ?? 0) < ($1.daysSinceWorn ?? 0) }) {
            return "Gets your \(idle.name.lowercased()) out again — unworn \(idle.daysSinceWorn ?? 0) days"
        }
        if let top = pieces.first(where: { $0.category == .top }), let bottom = pieces.first(where: { $0.category == .bottom }),
           signals.learned.fitShare(top) >= 0.3, signals.learned.fitShare(bottom) >= 0.3 {
            return "Your usual mix: \(top.fit.rawValue) top, \(bottom.silhouette ?? bottom.fit.rawValue) bottoms"
        }
        let accents = pieces.filter { !$0.isNeutral }
        if let accent = accents.first { return "\(accent.name) as the one pop of colour" }
        return "All neutrals, nothing to overthink"
    }
}
