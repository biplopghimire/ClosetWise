import Foundation

/// Where a piece goes in an outfit. A dress takes the place of a top and a bottom.
enum OutfitSlot: String, CaseIterable, Identifiable {
    case layer, top, dress, bottom, shoes, accessory
    var id: String { rawValue }

    init?(_ category: ItemCategory) {
        switch category {
        case .outerwear: self = .layer
        case .top: self = .top
        case .dress: self = .dress
        case .bottom: self = .bottom
        case .shoes: self = .shoes
        case .accessory: self = .accessory
        }
    }

    var category: ItemCategory {
        switch self {
        case .layer: .outerwear
        case .top: .top
        case .dress: .dress
        case .bottom: .bottom
        case .shoes: .shoes
        case .accessory: .accessory
        }
    }

    var title: String {
        switch self {
        case .layer: "Layer"
        case .top: "Top"
        case .dress: "Dress"
        case .bottom: "Bottom"
        case .shoes: "Shoes"
        case .accessory: "Accessory"
        }
    }

    /// Slots an outfit can leave empty.
    var isOptional: Bool { self == .layer || self == .accessory }
}

struct Outfit: Identifiable, Hashable {
    var id: String { Outfit.comboKey(pieces.map(\.id)) }
    /// Either top + bottom, or a dress.
    var top: WardrobeItem?
    var bottom: WardrobeItem?
    var dress: WardrobeItem?
    var shoes: WardrobeItem
    var layer: WardrobeItem?
    var accessory: WardrobeItem?
    var title: String
    var reason: String
    var score: Double
    /// How well the pieces suit the user's style, 0…100.
    var styleScore: Int = 60

    var pieces: [WardrobeItem] { [layer, top, dress, bottom, shoes, accessory].compactMap { $0 } }
    func contains(_ item: WardrobeItem) -> Bool { pieces.contains { $0.id == item.id } }

    func item(in slot: OutfitSlot) -> WardrobeItem? {
        switch slot {
        case .layer: layer
        case .top: top
        case .dress: dress
        case .bottom: bottom
        case .shoes: shoes
        case .accessory: accessory
        }
    }

    /// The slots this outfit uses (dress outfits have no top or bottom row).
    var slots: [OutfitSlot] { dress == nil ? [.layer, .top, .bottom, .shoes, .accessory] : [.layer, .dress, .shoes, .accessory] }

    static func comboKey(_ ids: [UUID]) -> String { ids.map(\.uuidString).sorted().joined(separator: "|") }
}

/// What kind of day the outfit is for. Sets how dressed up it should be.
enum Occasion: String, CaseIterable, Identifiable {
    case everyday, smart, goingOut, lounge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: "Everyday"
        case .smart: "Smart"
        case .goingOut: "Going out"
        case .lounge: "Lounge"
        }
    }

    /// Target average formality (1 lounge … 5 formal).
    var formality: Double {
        switch self {
        case .everyday: 2
        case .smart: 3.3
        case .goingOut: 3
        case .lounge: 1.2
        }
    }

    /// Pieces that don't belong at all.
    func allows(_ item: WardrobeItem) -> Bool {
        switch self {
        case .everyday: item.formality <= 4
        case .smart: item.formality >= 2 && item.kind != .hoodie && item.kind != .shorts
        case .goingOut: item.formality >= 2 && item.kind != .hoodie
        case .lounge: item.formality <= 2
        }
    }
}

/// What the engine knows about the user's taste.
struct StyleSignals {
    var preferences = StylePreferences()
    var learned = LearnedStyle()
    var disliked: Set<String> = []
    var loved: Set<String> = []
    /// Today's weather, when the user shared their location.
    var weather: WeatherNow?
    /// Outfits worn in the last week (combo keys), so ideas don't repeat what you just wore.
    var recentlyWorn: Set<String> = []
    /// What the day is for; nil = the user's usual dressiness.
    var occasion: Occasion?
}

/// Rule-based outfits from what the user already owns.
///
/// Style comes first: each piece is judged the way the purchase check judges it (fits, colours,
/// vibes, dressiness), and pieces have to go together (formality, shoes, colour, silhouette,
/// style family). Weather rules out what nobody should wear today. "Not worn lately" is only a
/// small tie-breaker, so ideas look like you rather than like whatever has been sitting unworn.
enum OutfitEngine {
    /// How many pieces per category one round combines. Small closets fit entirely; big ones are
    /// sampled (best-suited pieces plus some randomness), and the feed draws a new sample when it runs out.
    struct Caps { var tops = 14, bottoms = 9, shoes = 6, layers = 4, dresses = 6 }

    struct Ranking {
        var outfits: [Outfit]
        /// True when every piece was considered (nothing left out by the caps).
        var complete: Bool
    }

    // MARK: Public

    /// Outfits the closet can make that suit the user and today's weather, best first.
    static func rank(from items: [WardrobeItem], signals: StyleSignals = .init(), recentlyShown: [String: Date] = [:],
                     seed: UInt64? = nil, caps: Caps = .init()) -> [Outfit] {
        ranking(from: items, signals: signals, recentlyShown: recentlyShown, seed: seed, caps: caps).outfits
    }

    /// `recentlyShown` sinks outfits the user saw in the last few days, so ideas stay fresh;
    /// `seed` varies which pieces a big closet's round uses (nil = the best-suited ones).
    /// `locked` pins pieces into their slots (a locked dress rules out tops and bottoms).
    static func ranking(from items: [WardrobeItem], signals: StyleSignals = .init(), recentlyShown: [String: Date] = [:],
                        seed: UInt64? = nil, caps: Caps = .init(), locked: [WardrobeItem] = []) -> Ranking {
        let style = styleFits(items, signals)
        var rng = SplitMix64(seed: seed ?? 0)
        let lockedBySlot = Dictionary(locked.compactMap { item in OutfitSlot(item.category).map { ($0, item) } },
                                      uniquingKeysWith: { a, _ in a })
        let lockedIDs = Set(locked.map(\.id))

        // Pieces for one slot: the locked one, or those the weather and occasion allow,
        // best-suited first (with a shuffle when sampling).
        func pick(_ slot: OutfitSlot, _ cap: Int) -> (items: [WardrobeItem], all: Bool) {
            if let pinned = lockedBySlot[slot] { return ([pinned], true) }
            let pool = items.filter { item in
                OutfitSlot(item.category) == slot
                    && (signals.weather.map { Warmth.wearable(item, $0) } ?? true)
                    && (signals.occasion?.allows(item) ?? true)
            }
            guard pool.count > cap else { return (pool, true) }
            let ranked = pool.map { item -> (WardrobeItem, Double) in
                var p = Double(style[item.id]?.score ?? 60) / 10
                if seed != nil { p += Double(rng.next() % 1000) / 1000 * 4 }
                return (item, p)
            }
            return (ranked.sorted { $0.1 > $1.1 }.prefix(cap).map(\.0), false)
        }

        let wantsDress = lockedBySlot[.dress] != nil
        let wantsSeparates = lockedBySlot[.top] != nil || lockedBySlot[.bottom] != nil
        let none: (items: [WardrobeItem], all: Bool) = ([], true)
        let tops = wantsDress ? none : pick(.top, caps.tops)
        let bottoms = wantsDress ? none : pick(.bottom, caps.bottoms)
        let dresses = wantsSeparates ? none : pick(.dress, caps.dresses)
        let shoes = pick(.shoes, caps.shoes), layers = pick(.layer, caps.layers)
        let accessory = lockedBySlot[.accessory]
        let freshCutoff = Date.now.addingTimeInterval(-3 * 86_400)

        // Bases: top + bottom, or a dress. Each gets shoes, then plain and with up to two layers.
        var bases: [[WardrobeItem]] = []
        for top in tops.items { for bottom in bottoms.items { bases.append([top, bottom]) } }
        for dress in dresses.items { bases.append([dress]) }

        var kept: [(pieces: [WardrobeItem], score: Double)] = []
        for base in bases {
            for shoe in shoes.items {
                var plain: (pieces: [WardrobeItem], score: Double)?
                var layered: [(pieces: [WardrobeItem], score: Double)] = []
                let layerChoices: [WardrobeItem?] = lockedBySlot[.layer] != nil ? layers.items.map(Optional.some)
                    : [nil] + layers.items.map(Optional.some)
                for layer in layerChoices {
                    var pieces = (layer.map { [$0] } ?? []) + base + [shoe]
                    if let accessory { pieces.append(accessory) }
                    guard var s = score(pieces, signals: signals, style: style) else { continue }
                    let key = Outfit.comboKey(pieces.map(\.id))
                    if let seen = recentlyShown[key], seen > freshCutoff { s -= 1.2 }
                    if layer == nil { plain = (pieces, s) } else { layered.append((pieces, s)) }
                }
                if let plain { kept.append(plain) }
                kept += layered.sorted { $0.score > $1.score }.prefix(2)
            }
        }

        let outfits = kept
            .filter { $0.score > -8 && lockedIDs.isSubset(of: $0.pieces.map(\.id)) }
            .sorted { $0.score > $1.score }
            .compactMap { describe($0.pieces, score: $0.score, signals: signals, style: style) }
        let complete = tops.all && bottoms.all && dresses.all && shoes.all && layers.all
        return Ranking(outfits: outfits, complete: complete)
    }

    /// A varied handful of the best outfits. With a `seed` (e.g. the day), the pick rotates among
    /// the strong ones instead of always returning the single top-scorer.
    static func suggest(from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 6, seed: UInt64? = nil) -> [Outfit] {
        var ranked = rank(from: items, signals: signals)
        if let seed {
            // Keep the order roughly by quality but let near-ties trade places day to day.
            var rng = SplitMix64(seed: seed)
            ranked = ranked.prefix(40).map { o -> Outfit in var o = o; o.score += Double(rng.next() % 1000) / 1000 * 2.5; return o }
                .sorted { $0.score > $1.score } + ranked.dropFirst(40)
        }
        return diverse(ranked, limit: limit)
    }

    /// Outfits built around one piece: every piece in the closet gets some, whatever the weather.
    /// Accessories are added to the best outfits; a dress gets shoes and a layer.
    static func outfits(with item: WardrobeItem, from items: [WardrobeItem], signals: StyleSignals = .init(), limit: Int = 6) -> [Outfit] {
        var signals = signals
        signals.weather = nil       // an item page isn't about today
        signals.occasion = nil
        let generous = Caps(tops: 40, bottoms: 30, shoes: 20, layers: 10, dresses: 20)
        if item.category == .accessory {
            let base = rank(from: items, signals: signals)
            let withIt = diverse(base, limit: limit).compactMap { o -> Outfit? in
                var pieces = o.pieces.filter { $0.category != .accessory }
                pieces.append(item)
                return describe(pieces, score: o.score, signals: signals, style: styleFits(items, signals))
            }
            return withIt
        }
        let ranked = ranking(from: items, signals: signals, caps: generous, locked: [item]).outfits
        return diverse(ranked, limit: limit)
    }

    /// The best outfits that keep the `locked` pieces, varied. Drives Shuffle in the builder.
    static func best(from items: [WardrobeItem], locked: [WardrobeItem], signals: StyleSignals = .init(),
                     exclude: Set<String> = [], limit: Int = 30, seed: UInt64? = nil) -> [Outfit] {
        let ranked = ranking(from: items, signals: signals, seed: seed, locked: locked).outfits.filter { !exclude.contains($0.id) }
        if let seed {
            var rng = SplitMix64(seed: seed)
            let shuffled = ranked.prefix(60).map { o -> Outfit in var o = o; o.score += Double(rng.next() % 1000) / 1000 * 2; return o }
                .sorted { $0.score > $1.score }
            return diverse(shuffled + ranked.dropFirst(60), limit: limit)
        }
        return diverse(ranked, limit: limit)
    }

    /// Every piece that could go in `slot`, best-suited to the rest of `outfit` first.
    /// Pieces the weather or occasion rule out come last rather than disappearing, so swiping
    /// still reaches everything.
    static func alternatives(for slot: OutfitSlot, in outfit: Outfit, from items: [WardrobeItem],
                             signals: StyleSignals = .init()) -> [WardrobeItem] {
        let style = styleFits(items, signals)
        let others = outfit.pieces.filter { OutfitSlot($0.category) != slot }
        let candidates = items.filter { OutfitSlot($0.category) == slot }
        let scored = candidates.map { item -> (WardrobeItem, Double) in
            var pieces = others
            if slot == .dress { pieces.removeAll { $0.category == .top || $0.category == .bottom } }
            if slot == .top || slot == .bottom { pieces.removeAll { $0.category == .dress } }
            pieces.append(item)
            let s = score(pieces, signals: signals, style: style) ?? -20
            let allowed = signals.occasion?.allows(item) ?? true
            return (item, allowed ? s : s - 20)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Rebuilds an outfit with one slot changed (nil empties an optional slot), with fresh title and reason.
    static func replacing(_ slot: OutfitSlot, with item: WardrobeItem?, in outfit: Outfit, from items: [WardrobeItem],
                          signals: StyleSignals = .init()) -> Outfit? {
        var pieces = outfit.pieces.filter { OutfitSlot($0.category) != slot }
        if slot == .dress, item != nil { pieces.removeAll { $0.category == .top || $0.category == .bottom } }
        if slot == .top || slot == .bottom, item != nil { pieces.removeAll { $0.category == .dress } }
        if let item { pieces.append(item) }
        let style = styleFits(items, signals)
        let s = score(pieces, signals: signals, style: style) ?? -10
        return describe(pieces, score: s, signals: signals, style: style)
    }

    // MARK: Variety

    /// Greedy pick that keeps outfits from sharing most of their pieces or leaning on one piece.
    static func diverse(_ ranked: [Outfit], limit: Int) -> [Outfit] {
        var picked: [Outfit] = []
        var uses: [UUID: Int] = [:]
        for pass in 0..<2 where picked.count < limit {
            for outfit in ranked where picked.count < limit {
                if picked.contains(where: { $0.id == outfit.id }) { continue }
                if pass == 0 {
                    let ids = Set(outfit.pieces.map(\.id))
                    if picked.contains(where: { ids.intersection($0.pieces.map(\.id)).count >= max(2, ids.count - 1) }) { continue }
                    if outfit.pieces.contains(where: { (uses[$0.id] ?? 0) >= 2 }) { continue }
                }
                picked.append(outfit)
                outfit.pieces.forEach { uses[$0.id, default: 0] += 1 }
            }
        }
        return picked
    }

    // MARK: Scoring

    private static func styleFits(_ items: [WardrobeItem], _ signals: StyleSignals) -> [UUID: PurchaseCheckResult.StyleFit] {
        Dictionary(items.map { ($0.id, PurchaseCheckEngine.styleFit($0, signals: signals)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Scores one outfit; nil when the weather rules it out. Hot path: builds no strings.
    static func score(_ pieces: [WardrobeItem], signals: StyleSignals, style: [UUID: PurchaseCheckResult.StyleFit]) -> Double? {
        let key = Outfit.comboKey(pieces.map(\.id))
        if signals.disliked.contains(key) { return -20 }
        let clothes = pieces.filter { $0.category != .accessory }
        guard !clothes.isEmpty else { return nil }
        var s = 0.0

        // 1. Style: how well each piece suits the user. The biggest single factor.
        let fits = clothes.map { Double(style[$0.id]?.score ?? 60) }
        let avgFit = fits.reduce(0, +) / Double(fits.count)
        s += (avgFit - 60) / 10 * 1.6
        if let worst = fits.min(), worst < 40 { s -= (40 - worst) / 10 }   // one piece that isn't you spoils it

        // 2. Dressiness: pieces at the same level, shoes included, near the day's target.
        let formality = clothes.map { Double($0.formality) }
        let avg = formality.reduce(0, +) / Double(formality.count)
        s -= max(0, (formality.max() ?? 0) - (formality.min() ?? 0) - 1) * 1.5
        if let shoe = clothes.first(where: { $0.category == .shoes }), clothes.count > 1 {
            let rest = clothes.filter { $0.category != .shoes }.map { Double($0.formality) }
            let restAvg = rest.reduce(0, +) / Double(rest.count)
            s -= max(0, abs(Double(shoe.formality) - restAvg) - 1) * 1.2
        }
        let target = signals.occasion?.formality ?? signals.preferences.dressiness.map(Double.init) ?? signals.learned.formality
        s -= abs(avg - target) * (signals.occasion == nil ? 0.6 : 1.2)

        // 3. Style families: lounge, sporty, street, smart don't all mix.
        let families = Set(clothes.compactMap { family(of: $0) })
        if families.contains(.lounge) && families.contains(.smart) { s -= 2 }
        if families.contains(.sport) && families.contains(.smart) { s -= 1.5 }
        if families.count == 1 && clothes.count >= 3 { s += 0.4 }

        // 4. Colour: neutrals plus at most one accent; tonal outfits are a plus.
        let accents = clothes.filter { !$0.isNeutral }
        s -= Double(max(0, accents.count - 1)) * 1.6
        if accents.count == 1 { s += signals.occasion == .goingOut ? 0.8 : 0.4 }
        let accentHues = Set(accents.map { hueFamily($0.color) })
        if accents.count >= 2 && accentHues.count == 1 { s += 1.2 }   // same family (e.g. olive + green) reads as tonal
        let top = clothes.first { $0.category == .top }, bottom = clothes.first { $0.category == .bottom }
        if let top, let bottom {
            if top.color == bottom.color && !top.isNeutral { s -= 1 }
            if top.color == bottom.color && top.isNeutral && top.color != "black" && top.color != "denim" { s -= 0.4 }
        }

        // 5. Silhouette: balance volume, unless the user's look is relaxed all over.
        if let top, let bottom {
            let relaxedLook = signals.preferences.vibes.contains { ["Streetwear", "Grunge", "Y2K", "Sporty"].contains($0) }
                || signals.learned.tags.contains { $0.lowercased().contains("street") || $0.lowercased().contains("relaxed") }
            let t = top.fit.ease, b = bottom.fit.ease
            if t >= 4 && b >= 4 { s += relaxedLook ? 0.5 : -0.6 }
            if (t >= 4 && b <= 2) || (t <= 2 && b >= 4) { s += 0.4 }
            if t <= 1 && b <= 1 { s -= 0.3 }
        }

        // 5b. Season: a wool sweater or a coat doesn't go with shorts, a tank doesn't go under a parka.
        if clothes.contains(where: { $0.kind == .shorts }),
           clothes.contains(where: { $0.kind == .coat || ($0.category != .shoes && Warmth.of($0) >= 3) }) { s -= 1.5 }

        // 6. What they told us and what they keep coming back to.
        let prefs = signals.preferences
        for piece in clothes {
            if let wanted = prefs.fits[piece.category.rawValue] {
                let gap = abs(wanted.ease - piece.fit.ease)
                s += gap == 0 ? 0.4 : gap >= 2 ? -0.5 : 0
            }
            if prefs.avoidColors.contains(piece.color.lowercased()) { s -= 2 }
        }
        if let top, let bottom, signals.learned.lovedPairs.contains(LearnedStyle.pairKey(top.id, bottom.id)) { s += 0.8 }
        if signals.loved.contains(key) { s += 1 }

        // 7. Weather.
        if let weather = signals.weather {
            let fit = Warmth.fit(clothes, weather)
            if fit.blocked { return nil }
            s += fit.score
        } else if clothes.contains(where: { $0.category == .outerwear }) {
            s += 0.2
        }

        // 8. Small tie-breakers: don't repeat last week's outfit; give a long-unworn piece a nudge.
        if signals.recentlyWorn.contains(Outfit.comboKey(clothes.map(\.id))) { s -= 1.5 }
        let idlest = clothes.map { $0.daysSinceWorn ?? 0 }.max() ?? 0
        s += idlest >= 60 ? 0.5 : idlest >= 30 ? 0.3 : 0
        return s
    }

    private enum Family { case lounge, sport, street, casual, smart }

    private static func family(of item: WardrobeItem) -> Family? {
        let style = item.style.lowercased()
        if style.contains("lounge") || item.formality <= 1 && item.kind == .hoodie { return .lounge }
        if style.contains("sport") || style.contains("athle") || style.contains("gym") { return .sport }
        if style.contains("street") || style.contains("skate") { return .street }
        if style.contains("smart") || style.contains("formal") || style.contains("tailored") || item.formality >= 4 { return .smart }
        if style.contains("casual") { return .casual }
        return nil
    }

    private static func hueFamily(_ color: String) -> String {
        switch color.lowercased() {
        case "green", "olive", "khaki", "sage", "mint": "green"
        case "blue", "light blue", "teal", "turquoise": "blue"
        case "red", "burgundy", "maroon", "wine", "rust": "red"
        case "pink", "rose", "blush": "pink"
        case "orange", "coral", "peach": "orange"
        case "yellow", "mustard", "gold": "yellow"
        case "purple", "lilac", "lavender", "plum": "purple"
        default: color.lowercased()
        }
    }

    // MARK: Words

    /// Title and reason, written only for outfits that made the cut. nil if the pieces can't form an outfit.
    static func describe(_ pieces: [WardrobeItem], score: Double, signals: StyleSignals,
                         style: [UUID: PurchaseCheckResult.StyleFit]) -> Outfit? {
        let first = { (c: ItemCategory) in pieces.first { $0.category == c } }
        guard let shoes = first(.shoes) else { return nil }
        let dress = first(.dress), top = first(.top), bottom = first(.bottom)
        guard dress != nil || (top != nil && bottom != nil) else { return nil }
        let clothes = pieces.filter { $0.category != .accessory }
        let fits = clothes.compactMap { style[$0.id] }
        let styleScore = fits.isEmpty ? 60 : Double(fits.map(\.score).reduce(0, +)) / Double(fits.count)
        let weatherNote = signals.weather.flatMap { Warmth.note(clothes, $0) }
        let reasons = reasons(for: pieces, signals, styleFits: fits, styleScore: styleScore, weatherNote: weatherNote)
        let key = Outfit.comboKey(pieces.map(\.id))
        // Rotate among the three strongest reasons so a run of ideas doesn't repeat itself.
        let pick = reasons.count > 1 && !signals.loved.contains(key)
            ? key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % min(2, reasons.count) : 0
        return Outfit(top: dress == nil ? top : nil, bottom: dress == nil ? bottom : nil, dress: dress, shoes: shoes,
                      layer: first(.outerwear), accessory: first(.accessory),
                      title: title(for: clothes, signals), reason: reasons[pick], score: score,
                      styleScore: Int(styleScore.rounded()))
    }

    private static func title(for pieces: [WardrobeItem], _ signals: StyleSignals) -> String {
        if let occasion = signals.occasion, occasion != .everyday { return occasion == .goingOut ? "Going-out look" : "\(occasion.title) look" }
        let avg = Double(pieces.map(\.formality).reduce(0, +)) / Double(max(1, pieces.count))
        let base: String
        switch avg {
        case ..<1.6: base = "Easy weekend"
        case ..<2.4: base = "Everyday casual"
        case ..<3.2: base = "Smart casual"
        default: base = "Polished"
        }
        guard let weather = signals.weather else { return base }
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

        // Style, in the user's own terms, first.
        let vibe = styleFits.flatMap(\.reasons).first { $0.positive && $0.text.hasPrefix("Fits your") }
        if let vibe, styleScore >= 62 { out.append(vibe.text) }
        else if styleScore >= 75 {
            out.append("Very you — \(signals.learned.tags.prefix(2).joined(separator: ", ").lowercased().ifEmpty("your usual style"))")
        }
        if let weatherNote { out.append(weatherNote) }

        let top = pieces.first { $0.category == .top }, bottom = pieces.first { $0.category == .bottom }
        if let top, let bottom {
            if top.fit.ease >= 4 && bottom.fit.ease <= 2 { out.append("Roomy \(top.name.lowercased()) balanced by slimmer \(bottom.name.lowercased())") }
            else if signals.learned.fitShare(top) >= 0.3, signals.learned.fitShare(bottom) >= 0.3 {
                out.append("Your usual mix: \(top.fit.rawValue) top, \(bottom.silhouette ?? bottom.fit.rawValue) bottoms")
            }
        }
        let accents = pieces.filter { !$0.isNeutral && $0.category != .accessory }
        if accents.count == 1, let accent = accents.first { out.append("\(accent.name) as the one pop of colour") }
        else if accents.count >= 2 { out.append("Tonal \(hueFamily(accents[0].color)) from top to bottom") }
        if let accessory = pieces.first(where: { $0.category == .accessory }) { out.append("Finished with your \(accessory.name.lowercased())") }
        if let idle = pieces.filter({ ($0.daysSinceWorn ?? 0) >= 30 }).max(by: { ($0.daysSinceWorn ?? 0) < ($1.daysSinceWorn ?? 0) }) {
            out.append("Gets your \(idle.name.lowercased()) out again — unworn \(idle.daysSinceWorn ?? 0) days")
        }
        if out.isEmpty { out.append(accents.isEmpty ? "All neutrals, nothing to overthink" : "Easy pieces that work together") }
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
