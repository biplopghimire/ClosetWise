import Foundation
import Observation

/// An endless-feeling list of outfit ideas: the engine ranks every outfit the closet can make,
/// and the feed hands them out a page at a time as the user scrolls — varied (no two neighbours
/// share most of their pieces), with ones they haven't seen in the last few days first.
@MainActor
@Observable
final class OutfitFeed {
    private(set) var shown: [Outfit] = []
    /// Every outfit has been shown; adding pieces makes more.
    private(set) var exhausted = false
    /// How many outfits the closet can make today.
    private(set) var total = 0

    @ObservationIgnored private var queue: [Outfit] = []
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var items: [WardrobeItem] = []
    @ObservationIgnored private var signals = StyleSignals()
    @ObservationIgnored private var round: UInt64 = 0
    /// Every combination has been ranked (small closet), so an empty queue means truly done.
    @ObservationIgnored private var complete = true
    @ObservationIgnored private var history: [String: Date]
    @ObservationIgnored private let historyKey = "outfits.recentlyShown"

    init() {
        history = (UserDefaults.standard.dictionary(forKey: historyKey) as? [String: Date]) ?? [:]
    }

    /// Rebuilds the feed (closet, style or weather changed) and shows the first page.
    func reset(items: [WardrobeItem], signals: StyleSignals, fresh: Bool = false) {
        if fresh { history = [:] }
        self.items = items
        self.signals = signals
        seen = []
        shown = []
        queue = []
        total = 0
        round = UInt64.random(in: 1...UInt64.max / 2)
        exhausted = false
        refill()
        loadMore()
    }

    /// Ranks another round. Small closets are ranked whole in one go; big ones are sampled, so each
    /// round brings combinations the user hasn't seen yet.
    private func refill() {
        for _ in 0..<4 {
            round &+= 1
            let ranking = OutfitEngine.ranking(from: items, signals: signals, recentlyShown: history, seed: round)
            complete = ranking.complete
            // A little shuffle so the feed doesn't open on the same outfits every visit.
            var rng = SplitMix64(seed: round)
            let fresh = ranking.outfits.filter { !seen.contains($0.id) }
                .map { o -> Outfit in var o = o; o.score += Double(rng.next() % 1000) / 1000 * 0.8; return o }
                .sorted { $0.score > $1.score }
            fresh.forEach { seen.insert($0.id) }
            queue += fresh
            total += fresh.count
            if !fresh.isEmpty || complete { return }
        }
    }

    /// Appends the next page. Called when the user scrolls near the end.
    func loadMore(_ count: Int = 8) {
        if queue.count < count && !complete { refill() }
        guard !queue.isEmpty else { exhausted = true; return }
        var page: [Outfit] = []
        var uses: [UUID: Int] = [:]
        while page.count < count, !queue.isEmpty {
            let recent = (shown + page).suffix(4)
            let index = queue.prefix(80).firstIndex { candidate in
                let ids = Set(candidate.pieces.map(\.id))
                return !recent.contains { ids.intersection($0.pieces.map(\.id)).count >= 2 }
                    && !candidate.pieces.contains { (uses[$0.id] ?? 0) >= 2 }
            } ?? queue.startIndex
            let outfit = queue.remove(at: index)
            page.append(outfit)
            outfit.pieces.forEach { uses[$0.id, default: 0] += 1 }
        }
        shown += page
        if queue.isEmpty && !complete { refill() }
        exhausted = queue.isEmpty
        remember(page)
    }

    /// The user said "Not for me" — take it out of the feed.
    func drop(disliked: Set<String>) {
        shown.removeAll { disliked.contains($0.id) }
        queue.removeAll { disliked.contains($0.id) }
    }

    private func remember(_ page: [Outfit]) {
        let now = Date.now
        page.forEach { history[$0.id] = now }
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        history = history.filter { $0.value > cutoff }
        UserDefaults.standard.set(history, forKey: historyKey)
    }
}
