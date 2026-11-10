import Foundation

/// The evidence shown before checkout. The app never decides — it explains.
struct PurchaseCheckResult: Hashable {
    struct Similar: Hashable, Identifiable {
        var id: UUID { item.id }
        let item: WardrobeItem
        let score: Double          // 0…1
        let reasons: [String]      // "same colour", "same fit" …
        var level: String {
            switch score {
            case 0.85...: "Nearly identical"
            case 0.7...: "Very similar"
            default: "Similar"
            }
        }
    }

    struct StyleReason: Hashable {
        let text: String
        let positive: Bool
    }

    struct StyleFit: Hashable {
        let score: Int             // 0…100
        let reasons: [StyleReason]
        var label: String {
            switch score {
            case 75...: "Very you"
            case 55...: "Fits your style"
            case 40...: "A bit of a stretch"
            default: "Not really your style"
            }
        }
    }

    enum Verdict: String, Hashable {
        case addsValue = "Adds value"
        case consider = "Consider"
        case limitedGain = "Limited gain"
        case probablySkip = "Probably skip"
    }

    let product: WardrobeItem
    let duplicates: [Similar]
    let compatible: [WardrobeItem]
    let outfits: [Outfit]
    /// Outfits you can't already make with the closest thing you own.
    let newOutfitCount: Int
    let styleFit: StyleFit
    let predictedWearsPerYear: Double
    let costPerWear: Decimal?
    let verdict: Verdict
    var explanation: String

    var nearDuplicates: [Similar] { duplicates.filter { $0.score >= 0.85 } }
}

/// On-device purchase check: duplicates, compatibility, style fit and cost per wear,
/// computed from the closet, wear history and style profile. The backend refines the
/// explanation with Gemini when connected (`judge_purchase`).
enum PurchaseCheckEngine {
    static let similarThreshold = 0.58

    static func check(_ product: WardrobeItem, closet: [WardrobeItem], signals: StyleSignals) -> PurchaseCheckResult {
        let owned = closet.filter { $0.id != product.id }

        // Duplicates
        let duplicates = owned
            .map { item -> PurchaseCheckResult.Similar in
                let (score, reasons) = similarity(product, item)
                return .init(item: item, score: score, reasons: reasons)
            }
            .filter { $0.score >= similarThreshold }
            .sorted { $0.score > $1.score }

        // Compatibility
        let partners = owned.filter { partnerCategories(for: product.category).contains($0.category) }
        let compatible = partners.filter { pairScore(product, $0) >= 0 }
            .sorted { pairScore(product, $0) > pairScore(product, $1) }
        let outfits = outfitsWith(product, from: owned, signals: signals)
        let closest = duplicates.first?.item
        let newOutfits: Int
        if let closest {
            let existing = Set(outfitsWith(closest, from: owned.filter { $0.id != closest.id }, signals: signals)
                .map { Outfit.comboKey($0.pieces.filter { $0.id != closest.id }.map(\.id)) })
            newOutfits = outfits.filter { !existing.contains(Outfit.comboKey($0.pieces.filter { $0.id != product.id }.map(\.id))) }.count
        } else {
            newOutfits = outfits.count
        }

        // Style fit
        let styleFit = styleFit(product, signals: signals)

        // Predicted wear → cost per wear (2-year horizon)
        let peers = owned.filter { $0.category == product.category }.map(\.wearCount)
        let baseRate = peers.isEmpty ? 12 : Double(peers.sorted()[peers.count / 2])
        let styleFactor = min(1.3, max(0.35, Double(styleFit.score) / 65))
        let splitFactor = 1 / (1 + 0.6 * Double(duplicates.filter { $0.score >= 0.7 }.count))
        let compatFactor = min(1.2, 0.6 + Double(outfits.count) / 10)
        let wears = max(2, baseRate * styleFactor * splitFactor * compatFactor)
        let cpw = product.price.map { $0 / Decimal(max(1, (wears * 2).rounded())) }

        // Verdict
        let nearDup = duplicates.first { $0.score >= 0.85 }
        let verdict: PurchaseCheckResult.Verdict
        if nearDup != nil || (duplicates.count >= 3 && newOutfits <= 1) {
            verdict = .probablySkip
        } else if styleFit.score < 40 || outfits.isEmpty {
            verdict = .limitedGain
        } else if newOutfits >= 3 && styleFit.score >= 55 && duplicates.filter({ $0.score >= 0.7 }).isEmpty {
            verdict = .addsValue
        } else {
            verdict = .consider
        }

        var result = PurchaseCheckResult(product: product, duplicates: duplicates, compatible: compatible, outfits: outfits,
                                         newOutfitCount: newOutfits, styleFit: styleFit, predictedWearsPerYear: wears,
                                         costPerWear: cpw, verdict: verdict, explanation: "")
        result.explanation = explain(result)
        return result
    }

    // MARK: Similarity

    /// How interchangeable two pieces are, 0…1, with the reasons.
    static func similarity(_ a: WardrobeItem, _ b: WardrobeItem) -> (Double, [String]) {
        let categoryFactor: Double
        if a.category == b.category { categoryFactor = 1 }
        else if Set([a.category, b.category]) == [.top, .outerwear] && Set([a.kind, b.kind]).isSubset(of: [.shirt, .jacket, .knit, .hoodie]) { categoryFactor = 0.6 }
        else { return (0, []) }

        var reasons: [String] = []
        let kind = kindSimilarity(a.kind, b.kind)
        if kind == 1 { reasons.append("same type") }

        let colorSame = a.color.lowercased() == b.color.lowercased()
        let color = colorSame ? 1 : ColorMath.similarity(a.hex, b.hex)
        if color >= 0.75 { reasons.append("same colour") } else if color >= 0.45 { reasons.append("similar colour") }

        let easeGap = abs(a.fit.ease - b.fit.ease)
        let fit = max(0, 1 - Double(easeGap) / 3)
        if easeGap == 0 { reasons.append("same fit") }

        let cutA = tokens(a.silhouette), cutB = tokens(b.silhouette)
        let cut = (cutA.isEmpty || cutB.isEmpty) ? 0.4 : jaccard(cutA, cutB)
        if cut >= 0.5 { reasons.append("same cut") }

        let matA = tokens(a.material), matB = tokens(b.material)
        let material = (matA.isEmpty || matB.isEmpty) ? 0.4 : max(jaccard(matA, matB), matA.intersection(matB).isEmpty ? 0 : 0.6)
        if material >= 0.6 { reasons.append("same fabric") }

        let formality = max(0, 1 - Double(abs(a.formality - b.formality)) / 3)

        var score = (kind * 0.25 + color * 0.30 + fit * 0.15 + cut * 0.12 + material * 0.08 + formality * 0.10) * categoryFactor
        // A clearly different colour is a different piece in practice, even with the same cut.
        if color < 0.2 { score *= 0.85 }
        return (score, reasons)
    }

    static func kindSimilarity(_ a: GarmentKind, _ b: GarmentKind) -> Double {
        if a == b { return 1 }
        let related: [Set<GarmentKind>: Double] = [
            [.tee, .knit]: 0.6, [.knit, .hoodie]: 0.6, [.tee, .hoodie]: 0.4, [.shirt, .jacket]: 0.5,
            [.jacket, .coat]: 0.6, [.knit, .shirt]: 0.35, [.trousers, .shorts]: 0.3, [.trousers, .skirt]: 0.2, [.skirt, .shorts]: 0.3,
        ]
        return related[[a, b]] ?? 0.15
    }

    private static func tokens(_ s: String?) -> Set<String> {
        Set((s ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 2 })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let u = a.union(b).count
        return u == 0 ? 0 : Double(a.intersection(b).count) / Double(u)
    }

    // MARK: Compatibility

    static func partnerCategories(for c: ItemCategory) -> Set<ItemCategory> {
        switch c {
        case .top: [.bottom, .shoes, .outerwear]
        case .bottom: [.top, .shoes, .outerwear]
        case .outerwear: [.top, .bottom, .shoes]
        case .shoes: [.top, .bottom, .outerwear]
        case .dress: [.shoes, .outerwear]
        case .accessory: [.top, .bottom, .outerwear]
        }
    }

    /// ≥ 0 means the two work together.
    static func pairScore(_ a: WardrobeItem, _ b: WardrobeItem) -> Double {
        var s = 1.0
        let gap = abs(a.formality - b.formality)
        if gap >= 2 { s -= Double(gap - 1) * 0.9 }
        if !a.isNeutral && !b.isNeutral {
            s -= a.color.lowercased() == b.color.lowercased() ? 0.6 : (ColorMath.deltaE(a.hex, b.hex) > 45 ? 1.2 : 0.4)
        }
        // Volume balance: very loose on very loose can look shapeless, very tight on very tight too.
        if (a.category == .top && b.category == .bottom) || (a.category == .bottom && b.category == .top) {
            if a.fit.ease >= 4 && b.fit.ease >= 4 { s -= 0.3 }
            if a.fit.ease <= 0 && b.fit.ease <= 0 { s -= 0.3 }
        }
        return s
    }

    /// Complete outfits (top + bottom + shoes) that include the product, every pair compatible.
    static func outfitsWith(_ product: WardrobeItem, from closet: [WardrobeItem], signals: StyleSignals) -> [Outfit] {
        var tops = closet.filter { $0.category == .top }
        var bottoms = closet.filter { $0.category == .bottom }
        var shoes = closet.filter { $0.category == .shoes }
        var layers: [WardrobeItem?] = [nil]
        switch product.category {
        case .top: tops = [product]
        case .bottom: bottoms = [product]
        case .shoes: shoes = [product]
        case .outerwear: layers = [product]
        default: return []
        }
        var result: [Outfit] = []
        for t in tops { for b in bottoms { for sh in shoes { for l in layers {
            let pieces = [l, t, b, sh].compactMap { $0 }
            var ok = true
            outer: for i in 0..<pieces.count { for j in (i + 1)..<pieces.count where pairScore(pieces[i], pieces[j]) < 0 { ok = false; break outer } }
            guard ok else { continue }
            let key = Outfit.comboKey(pieces.map(\.id))
            guard !signals.disliked.contains(key) else { continue }
            result.append(Outfit(top: t, bottom: b, shoes: sh, layer: l, title: "", reason: "", score: 0))
        } } } }
        return result
    }

    // MARK: Style fit

    static func styleFit(_ p: WardrobeItem, signals: StyleSignals) -> PurchaseCheckResult.StyleFit {
        let prefs = signals.preferences, learned = signals.learned
        var score = 60.0
        var reasons: [PurchaseCheckResult.StyleReason] = []
        func add(_ delta: Double, _ text: String) { score += delta; reasons.append(.init(text: text, positive: delta >= 0)) }
        let catName = p.category.filterTitle.lowercased()

        // Fit — stated preference first, then what they actually wear.
        if let wanted = prefs.fits[p.category.rawValue] {
            let gap = abs(wanted.ease - p.fit.ease)
            if gap == 0 { add(14, "\(p.fit.label) — the fit you said you like for \(catName)") }
            else if gap >= 2 { add(-16, "\(p.fit.label), but you prefer \(wanted.rawValue) \(catName)") }
        }
        if let usual = learned.topFit(p.category), learned.outfitCount >= 3 {
            let share = learned.fitShare(p)
            if share >= 0.35 { add(10, "\(p.fit.label) — how you usually wear \(catName) (\(Int(share * 100))%)") }
            else if abs(usual.value.ease - p.fit.ease) >= 2 { add(-10, "\(p.fit.label) — you mostly wear \(usual.value.rawValue) \(catName)") }
        }

        // Cut
        if let cut = p.silhouette?.lowercased(), let usualCut = learned.silhouettes[p.category]?.first, usualCut.share >= 0.3 {
            if cut.contains(usualCut.value.lowercased()) || usualCut.value.lowercased().contains(cut) {
                add(8, "\(cut.capitalized) — your go-to cut")
            }
        }

        // Colour
        let color = p.color.lowercased()
        if prefs.avoidColors.contains(color) { add(-30, "\(color.capitalized) is a colour you avoid") }
        else if prefs.loveColors.contains(color) { add(12, "\(color.capitalized) is a colour you love") }
        if let worn = learned.colors.first(where: { $0.value == color }), worn.share >= 0.1 {
            add(6, "You wear a lot of \(color) (\(Int(worn.share * 100))% of outfits)")
        } else if !p.isNeutral && learned.outfitCount >= 3 && !prefs.loveColors.contains(color) {
            add(-6, "\(color.capitalized) is new for you — mostly you wear \(learned.neutralShare >= 0.6 ? "neutrals" : "other colours")")
        }

        // Dressiness
        let target = prefs.dressiness.map(Double.init) ?? learned.formality
        let gap = Double(p.formality) - target
        if abs(gap) <= 0.8 { add(6, "Matches how dressed up you usually are") }
        else if gap > 1.5 { add(-12, "Dressier than you usually go") }
        else if gap < -1.5 { add(-10, "More casual than you usually go") }

        // Vibes
        for vibe in prefs.vibes {
            if let fits = vibeMatch(vibe, p) { add(fits ? 8 : -5, fits ? "Fits your \(vibe.lowercased()) vibe" : "Not very \(vibe.lowercased())") }
        }

        // Words they used ("nothing too tight", "wide-leg everything").
        let words = prefs.about.lowercased()
        if !words.isEmpty {
            if (words.contains("tight") && (words.contains("no ") || words.contains("nothing") || words.contains("not "))) && p.fit.ease <= 1 {
                add(-12, "You said you don't like things too tight")
            }
            if let cut = p.silhouette?.lowercased(), !cut.isEmpty, words.contains(cut) { add(8, "You mentioned \(cut) in your style notes") }
        }

        return .init(score: Int(min(100, max(0, score)).rounded()), reasons: reasons)
    }

    /// nil = the vibe says nothing about this piece.
    static func vibeMatch(_ vibe: String, _ p: WardrobeItem) -> Bool? {
        let color = p.color.lowercased()
        switch vibe.lowercased() {
        case "minimal", "scandi": return p.isNeutral && (1...3).contains(p.fit.ease) && p.kind != .hoodie
        case "streetwear": return p.fit.ease >= 4 || [.hoodie, .shoes].contains(p.kind) ? true : (p.fit.ease <= 1 ? false : nil)
        case "classic", "preppy": return [.shirt, .coat, .jacket].contains(p.kind) || p.formality >= 3 ? true : (p.kind == .hoodie ? false : nil)
        case "quiet luxury": return p.isNeutral && p.formality >= 3 ? true : (!p.isNeutral ? false : nil)
        case "sporty": return [.hoodie, .shorts].contains(p.kind) || p.style.contains("sport") ? true : (p.formality >= 4 ? false : nil)
        case "edgy", "grunge": return color == "black" || p.material.contains("leather") ? true : nil
        case "romantic", "boho": return p.kind == .skirt || ["pink", "cream", "purple"].contains(color) ? true : nil
        case "workwear": return [.jacket, .trousers].contains(p.kind) && (p.material.contains("denim") || p.material.contains("canvas") || p.material.contains("cotton")) ? true : nil
        case "smart casual": return (2...4).contains(p.formality) ? true : (p.formality == 1 ? false : nil)
        case "coastal": return ["white", "cream", "blue", "navy", "beige"].contains(color) ? true : nil
        default: return nil
        }
    }

    // MARK: Explanation

    static func explain(_ r: PurchaseCheckResult) -> String {
        var parts: [String] = []
        if let top = r.duplicates.first {
            let others = r.duplicates.count - 1
            parts.append("It's \(top.level.lowercased()) to your \(top.item.name.lowercased())" + (others > 0 ? " and \(others) other piece\(others == 1 ? "" : "s")" : "") + ".")
            let idle = r.duplicates.filter { ($0.item.daysSinceWorn ?? 0) >= 30 }
            if !idle.isEmpty { parts.append("\(idle.count == 1 ? "One of those hasn't" : "\(idle.count) of those haven't") been worn in a month or more.") }
        }
        if r.outfits.isEmpty {
            parts.append("Nothing in your closet makes a full outfit with it yet.")
        } else {
            parts.append("It makes \(r.outfits.count) outfit\(r.outfits.count == 1 ? "" : "s") with what you own" +
                         (r.duplicates.isEmpty ? "." : ", \(r.newOutfitCount) you can't already make."))
        }
        parts.append("Style fit: \(r.styleFit.label.lowercased()).")
        return parts.joined(separator: " ")
    }
}
