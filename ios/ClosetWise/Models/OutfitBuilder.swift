import Foundation
import Observation

/// State for the Outfits tab: one outfit at a time, a swipeable row per slot, locks, and
/// ClosetWise's ranked picks.
///
/// "ClosetWise pick" walks down the ranking — #1, #2, #3 … — where every pick is a genuinely
/// different outfit (at least two main pieces change), never #1 with new shoes. Locking a row
/// re-ranks around that piece and asks Gemini which of the user's pieces go best with it; those
/// get a sparkle badge in their rows.
///
/// Rows are ordered once per outfit (best match for the rest of the outfit first) and keep that
/// order while the user swipes, so pieces don't jump around under their finger.
@MainActor
@Observable
final class OutfitBuilder {
    struct Entry: Identifiable, Hashable {
        let id: UUID
        /// nil = "none" (only in optional rows: layer, accessory).
        let item: WardrobeItem?
    }

    struct Row: Identifiable {
        let slot: OutfitSlot
        var entries: [Entry]
        var id: OutfitSlot { slot }
    }

    enum Mode { case separates, dress }

    /// Where the sparkle-badged pieces came from.
    enum SuggestionSource: Equatable { case gemini, closetWise }

    static let noneID = UUID(uuidString: "00000000-0000-0000-0000-0000000F0000")!

    private(set) var outfit: Outfit?
    private(set) var rows: [Row] = []
    /// Which entry each row is showing (bound to the row's scroll position).
    var selection: [OutfitSlot: UUID] = [:]
    private(set) var locked: Set<OutfitSlot> = []
    private(set) var occasion: Occasion?

    /// ClosetWise's ranked, distinct outfits for the current locks and occasion.
    private(set) var picks: [Outfit] = []
    /// Which pick is showing (nil once the user swipes away from it).
    private(set) var pickIndex: Int?
    /// Bumped on every pick, for haptics and animations.
    private(set) var pickCount = 0

    /// Pieces suggested to go with the locked ones, per row (sparkle badge).
    /// Best first.
    private(set) var suggested: [OutfitSlot: [UUID]] = [:]
    private(set) var suggestionSource: SuggestionSource?
    private(set) var suggestionNote: String?
    private(set) var suggesting = false

    @ObservationIgnored private var items: [WardrobeItem] = []
    @ObservationIgnored private var signals = StyleSignals()
    @ObservationIgnored private var profile: StyleContext?
    @ObservationIgnored private var closetSignature = ""
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    var mode: Mode { outfit?.dress == nil ? .separates : .dress }
    var hasDresses: Bool { items.contains { $0.category == .dress } }
    var hasSeparates: Bool { items.contains { $0.category == .top } && items.contains { $0.category == .bottom } }
    /// The closet can make at least one outfit.
    var canBuild: Bool { items.contains { $0.category == .shoes } && (hasSeparates || hasDresses) }
    var lockedItems: [WardrobeItem] { locked.compactMap { outfit?.item(in: $0) } }

    // MARK: Setup

    /// Call when the closet, style or weather changes. Keeps the current look if its pieces still exist.
    func configure(items: [WardrobeItem], signals: StyleSignals, profile: StyleContext) {
        var signals = signals
        signals.occasion = occasion
        let signature = items.map { "\($0.id)\($0.updatedAt?.timeIntervalSince1970 ?? 0)" }.joined()
        let closetChanged = signature != closetSignature
        self.items = items
        self.signals = signals
        self.profile = profile
        closetSignature = signature
        if let outfit, !closetChanged, outfit.pieces.allSatisfy({ p in items.contains { $0.id == p.id } }) {
            rerank(keepingCurrent: true)
            rebuild(around: outfit)
        } else {
            rerank(keepingCurrent: false)
            showPick(0)
        }
    }

    /// Opens the builder on one piece, locked in place.
    func start(with item: WardrobeItem) {
        guard let slot = OutfitSlot(item.category) else { return }
        locked = [slot]
        picks = OutfitEngine.picks(from: OutfitEngine.ranking(from: items, signals: signals, locked: [item]).outfits, fixed: [item.id])
        if picks.isEmpty {
            // The weather or occasion ruled everything out; still show how to wear it.
            picks = OutfitEngine.outfits(with: item, from: items, signals: signals, limit: 10)
        }
        showPick(0)
        suggest()
    }

    // MARK: Actions

    /// The next ClosetWise pick: #1, then #2 … and round again at the end.
    func nextPick() {
        guard !picks.isEmpty else { return }
        let next = pickIndex.map { ($0 + 1) % picks.count } ?? 0
        showPick(next)
        pickCount += 1
    }

    func toggleLock(_ slot: OutfitSlot) {
        if locked.contains(slot) { locked.remove(slot) } else { locked.insert(slot) }
        rerank(keepingCurrent: true)
        suggest()
    }

    func setOccasion(_ new: Occasion?) {
        guard new != occasion else { return }
        occasion = new
        signals.occasion = new
        rerank(keepingCurrent: false)
        showPick(0)
        suggest()
    }

    /// Switches between separates and a dress, keeping shoes and layer if they're locked.
    func setMode(_ new: Mode) {
        guard new != mode else { return }
        locked.subtract([.top, .bottom, .dress])
        let looks = OutfitEngine.best(from: items, locked: lockedItems, signals: signals, limit: 40)
        let wanted = looks.filter { ($0.dress != nil) == (new == .dress) }
        guard !wanted.isEmpty else { return }
        picks = OutfitEngine.picks(from: wanted, fixed: Set(lockedItems.map(\.id)))
        showPick(0)
        suggest()
    }

    /// The user swiped a row to another piece.
    func select(_ slot: OutfitSlot, entry id: UUID?) {
        guard let id, let outfit, let row = rows.first(where: { $0.slot == slot }),
              let entry = row.entries.first(where: { $0.id == id }) else { return }
        guard outfit.item(in: slot)?.id != entry.item?.id else { return }
        if let changed = OutfitEngine.replacing(slot, with: entry.item, in: outfit, from: items, signals: signals) {
            self.outfit = changed
            pickIndex = picks.firstIndex { $0.id == changed.id }
        }
    }

    /// Puts the suggested pieces on: the top suggestion in every unlocked row.
    func wearSuggestions() {
        guard var look = outfit else { return }
        for (slot, ids) in suggested where !locked.contains(slot) {
            guard let bestID = ids.first, let best = items.first(where: { $0.id == bestID }),
                  let changed = OutfitEngine.replacing(slot, with: best, in: look, from: items, signals: signals) else { continue }
            look = changed
        }
        pickIndex = picks.firstIndex { $0.id == look.id }
        rebuild(around: look)
    }

    // MARK: Internals

    /// Re-ranks for the current locks and occasion. A locked empty slot (e.g. "no layer") keeps
    /// outfits without one.
    private func rerank(keepingCurrent: Bool) {
        let keep = lockedItems
        let emptyLocked = locked.filter { outfit?.item(in: $0) == nil }
        let ranked = OutfitEngine.ranking(from: items, signals: signals, locked: keep).outfits
            .filter { look in emptyLocked.allSatisfy { look.item(in: $0) == nil } }
        picks = OutfitEngine.picks(from: ranked, fixed: Set(keep.map(\.id)))
        pickIndex = keepingCurrent ? picks.firstIndex { $0.id == outfit?.id } : nil
    }

    private func showPick(_ index: Int) {
        guard canBuild, picks.indices.contains(index) else {
            if !canBuild { outfit = nil; rows = [] }
            return
        }
        pickIndex = index
        rebuild(around: picks[index])
    }

    private func rebuild(around look: Outfit) {
        outfit = look
        rows = look.slots.compactMap { slot -> Row? in
            let ranked = OutfitEngine.alternatives(for: slot, in: look, from: items, signals: signals)
            guard !ranked.isEmpty || look.item(in: slot) != nil else { return nil }
            var entries = ranked.map { Entry(id: $0.id, item: $0) }
            if slot.isOptional { entries.insert(Entry(id: Self.noneID, item: nil), at: 0) }
            return Row(slot: slot, entries: entries)
        }
        selection = Dictionary(uniqueKeysWithValues: rows.map { ($0.slot, look.item(in: $0.slot)?.id ?? Self.noneID) })
    }

    /// Marks the pieces that go best with the locked ones. Shows ClosetWise's own best matches at
    /// once, then Gemini's picks when they arrive (if there's a backend and a Gemini key).
    private func suggest() {
        suggestionTask?.cancel()
        let anchors = lockedItems
        guard !anchors.isEmpty, let look = outfit else {
            suggested = [:]; suggestionSource = nil; suggestionNote = nil; suggesting = false
            return
        }
        let open = look.slots.filter { !locked.contains($0) }
        var candidates: [OutfitSlot: [WardrobeItem]] = [:]
        for slot in open {
            candidates[slot] = OutfitEngine.alternatives(for: slot, in: look, from: items, signals: signals)
        }
        // ClosetWise's best two per row, straight away.
        suggested = candidates.mapValues { Array($0.prefix(2).map(\.id)) }
        suggestionSource = .closetWise
        suggestionNote = nil

        guard let profile, SupabaseService.isConfigured, GeminiKey.current != nil else { return }
        suggesting = true
        suggestionTask = Task { [weak self] in
            let result = try? await PairingService.picks(locked: anchors, candidates: candidates, profile: profile)
            guard let self, !Task.isCancelled else { return }
            self.suggesting = false
            guard let result, !result.picks.isEmpty, Set(self.lockedItems.map(\.id)) == Set(anchors.map(\.id)) else { return }
            self.suggested = result.picks.filter { !$0.value.isEmpty }
            self.suggestionSource = .gemini
            self.suggestionNote = result.note
        }
    }
}
