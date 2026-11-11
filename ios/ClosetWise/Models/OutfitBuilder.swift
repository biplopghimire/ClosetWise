import Foundation
import Observation

/// State for the Outfits screen: one outfit at a time, a swipeable row per slot, locks, Shuffle.
///
/// Rows are ordered once per outfit (best match for the rest of the outfit first) and keep that
/// order while the user swipes, so pieces don't jump around under their finger. Shuffle draws
/// the next-best varied outfit that keeps the locked pieces, and never repeats until it has
/// shown everything it can make.
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

    static let noneID = UUID(uuidString: "00000000-0000-0000-0000-0000000F0000")!

    private(set) var outfit: Outfit?
    private(set) var rows: [Row] = []
    /// Which entry each row is showing (bound to the row's scroll position).
    var selection: [OutfitSlot: UUID] = [:]
    private(set) var locked: Set<OutfitSlot> = []
    private(set) var occasion: Occasion?
    /// Bumped on every Shuffle, for haptics and animations.
    private(set) var shuffles = 0

    @ObservationIgnored private var items: [WardrobeItem] = []
    @ObservationIgnored private var signals = StyleSignals()
    @ObservationIgnored private var queue: [Outfit] = []
    @ObservationIgnored private var shown: Set<String> = []
    @ObservationIgnored private var seed = UInt64.random(in: 1...UInt64.max / 2)
    @ObservationIgnored private var closetSignature = ""

    var mode: Mode { outfit?.dress == nil ? .separates : .dress }
    var hasDresses: Bool { items.contains { $0.category == .dress } }
    var hasSeparates: Bool { items.contains { $0.category == .top } && items.contains { $0.category == .bottom } }
    /// The closet can make at least one outfit.
    var canBuild: Bool { items.contains { $0.category == .shoes } && (hasSeparates || hasDresses) }

    // MARK: Setup

    /// Call when the closet, style or weather changes. Keeps the current look if its pieces still exist.
    func configure(items: [WardrobeItem], signals: StyleSignals) {
        var signals = signals
        signals.occasion = occasion
        let signature = items.map { "\($0.id)\($0.updatedAt?.timeIntervalSince1970 ?? 0)" }.joined()
        let closetChanged = signature != closetSignature
        self.items = items
        self.signals = signals
        closetSignature = signature
        queue = []
        if closetChanged { shown = [] }
        if let outfit, outfit.pieces.allSatisfy({ p in items.contains { $0.id == p.id } }), !closetChanged {
            rebuild(around: outfit)
        } else {
            shuffle()
        }
    }

    /// Opens the builder on one piece, locked in place.
    func start(with item: WardrobeItem) {
        guard let slot = OutfitSlot(item.category) else { return }
        locked = [slot]
        queue = []
        shown = []
        if let look = OutfitEngine.best(from: items, locked: [item], signals: signals, limit: 1, seed: seed).first {
            show(look)
        } else if let look = OutfitEngine.outfits(with: item, from: items, signals: signals, limit: 1).first {
            show(look)   // the weather or occasion ruled everything out; still show how to wear it
        }
    }

    // MARK: Actions

    /// Next varied outfit that keeps the locked pieces.
    func shuffle() {
        guard canBuild else { outfit = nil; rows = []; return }
        if queue.isEmpty { refill() }
        if queue.isEmpty { shown = []; refill() }   // seen everything: go round again
        guard !queue.isEmpty else { return }
        // Prefer a look that changes most of the unlocked pieces, so Shuffle feels like a new outfit
        // rather than the same one with different shoes.
        let free = (outfit?.slots ?? []).filter { !locked.contains($0) && !$0.isOptional }
        let index = queue.firstIndex { candidate in
            let changed = free.filter { candidate.item(in: $0)?.id != outfit?.item(in: $0)?.id }.count
            return changed * 2 >= max(1, free.count)
        } ?? 0
        show(queue.remove(at: index))
        shuffles += 1
    }

    func toggleLock(_ slot: OutfitSlot) {
        if locked.contains(slot) { locked.remove(slot) } else { locked.insert(slot) }
        queue = []
    }

    func setOccasion(_ new: Occasion?) {
        guard new != occasion else { return }
        occasion = new
        signals.occasion = new
        queue = []
        shown = []
        shuffle()
    }

    /// Switches between separates and a dress, keeping shoes and layer if they're locked.
    func setMode(_ new: Mode) {
        guard new != mode else { return }
        locked.subtract([.top, .bottom, .dress])
        queue = []
        let keep = lockedItems
        let looks = OutfitEngine.best(from: items, locked: keep, signals: signals, limit: 40, seed: seed &+ 7)
        if let look = looks.first(where: { ($0.dress != nil) == (new == .dress) }) { show(look) }
    }

    /// The user swiped a row to another piece.
    func select(_ slot: OutfitSlot, entry id: UUID?) {
        guard let id, let outfit, let row = rows.first(where: { $0.slot == slot }),
              let entry = row.entries.first(where: { $0.id == id }) else { return }
        guard outfit.item(in: slot)?.id != entry.item?.id else { return }
        if let changed = OutfitEngine.replacing(slot, with: entry.item, in: outfit, from: items, signals: signals) {
            self.outfit = changed
        }
    }

    // MARK: Internals

    private var lockedItems: [WardrobeItem] { locked.compactMap { outfit?.item(in: $0) } }

    private func refill() {
        seed &+= 1
        let keep = lockedItems
        // A locked empty slot (e.g. "no layer") keeps outfits without one.
        let emptyLocked = locked.filter { outfit?.item(in: $0) == nil }
        queue = OutfitEngine.best(from: items, locked: keep, signals: signals, exclude: shown, limit: 30, seed: seed)
            .filter { look in emptyLocked.allSatisfy { look.item(in: $0) == nil } }
    }

    private func show(_ look: Outfit) {
        shown.insert(look.id)
        rebuild(around: look)
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
}
