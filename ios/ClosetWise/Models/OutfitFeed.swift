import Foundation
import Observation

/// An endless feed of outfit ideas.
///
/// The engine ranks outfits in the background; the feed hands them out a page at a time as the
/// user scrolls, keeping neighbours varied and putting ones they haven't seen lately first.
/// Big closets are sampled a round at a time, so new combinations keep coming. When a small
/// closet has shown everything it can make, a new round starts with the same outfits in a fresh
/// order — the feed never runs dry while the closet can make at least one outfit.
@MainActor
@Observable
final class OutfitFeed {
    struct Entry: Identifiable, Hashable {
        /// Position in the feed (outfits can come back in later rounds, so the outfit id isn't unique).
        let id: Int
        let outfit: Outfit
    }

    struct Round: Identifiable {
        let id: Int
        var entries: [Entry] = []
    }

    private(set) var rounds: [Round] = []
    /// Waiting for the next batch from the engine (shown as a spinner at the bottom).
    private(set) var loading = false
    /// The closet can't make a single outfit (or none suits today's weather).
    private(set) var empty = false
    /// Different outfits found so far.
    private(set) var distinct = 0

    var count: Int { rounds.reduce(0) { $0 + $1.entries.count } }
    var isEmpty: Bool { count == 0 }
    private var lastEntryID: Int { rounds.last?.entries.last?.id ?? -1 }

    @ObservationIgnored private var queue: [Outfit] = []
    @ObservationIgnored private var seenThisCycle: Set<String> = []
    @ObservationIgnored private var everSeen: Set<String> = []
    @ObservationIgnored private var items: [WardrobeItem] = []
    @ObservationIgnored private var signals = StyleSignals()
    @ObservationIgnored private var seed: UInt64 = 0
    @ObservationIgnored private var nextEntryID = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var rankTask: Task<Void, Never>?
    @ObservationIgnored private var waitingForPage = false
    /// Outfits the user turned down since the feed was built; later rounds skip them too.
    @ObservationIgnored private var dropped: Set<String> = []
    @ObservationIgnored private var fruitlessRounds = 0
    @ObservationIgnored private var history: [String: Date]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let historyKey = "outfits.recentlyShown"
    private static let pageSize = 10

    init() {
        history = (UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: Date]) ?? [:]
    }

    // MARK: Public

    /// Rebuilds the feed (closet, style or weather changed). Ranking happens in the background.
    func reset(items: [WardrobeItem], signals: StyleSignals) {
        generation += 1
        rankTask?.cancel()
        rankTask = nil
        self.items = items
        self.signals = signals
        rounds = [Round(id: 0)]
        dropped = signals.disliked
        queue = []
        seenThisCycle = []
        everSeen = []
        distinct = 0
        empty = false
        fruitlessRounds = 0
        seed = UInt64.random(in: 1...UInt64.max / 2)
        waitingForPage = true
        loading = true
        refill()
    }

    /// Shows the next page; asks the engine for more well before the queue runs out.
    func loadMore() {
        if queue.count < Self.pageSize * 3 { refill() }
        guard !queue.isEmpty else {
            waitingForPage = true
            loading = !empty
            return
        }
        waitingForPage = false
        loading = false
        appendPage()
        if queue.count < Self.pageSize * 3 { refill() }
    }

    /// True for entries near the end of the feed — time to fetch the next page.
    func shouldLoadMore(after entry: Entry) -> Bool { entry.id >= lastEntryID - 8 }

    /// The pieces the feed combines, so their pictures can be drawn ahead of time.
    var pieces: [WardrobeItem] { items }

    /// The user said "Not for me" — take it out of the feed.
    func drop(disliked: Set<String>) {
        dropped.formUnion(disliked)
        for i in rounds.indices { rounds[i].entries.removeAll { disliked.contains($0.outfit.id) } }
        queue.removeAll { disliked.contains($0.id) }
    }

    // MARK: Paging

    private func appendPage() {
        var page: [Entry] = []
        var uses: [UUID: Int] = [:]
        let earlier = rounds[rounds.count - 1].entries.suffix(4).map(\.outfit)
        while page.count < Self.pageSize, !queue.isEmpty {
            let recent = (earlier + page.map(\.outfit)).suffix(4)
            let index = queue.prefix(80).firstIndex { candidate in
                let ids = Set(candidate.pieces.map(\.id))
                return !recent.contains { ids.intersection($0.pieces.map(\.id)).count >= 2 }
                    && !candidate.pieces.contains { (uses[$0.id] ?? 0) >= 3 }
            } ?? queue.startIndex
            let outfit = queue.remove(at: index)
            page.append(Entry(id: nextEntryID, outfit: outfit))
            nextEntryID += 1
            outfit.pieces.forEach { uses[$0.id, default: 0] += 1 }
        }
        rounds[rounds.count - 1].entries += page
        remember(page.map(\.outfit))
    }

    // MARK: Ranking (background)

    private func refill() {
        guard rankTask == nil, !empty else { return }
        let items = self.items, signals = self.signals, history = self.history
        seed &+= 1
        let seed = self.seed
        let generation = self.generation
        rankTask = Task { [weak self] in
            let ranking = await Task.detached(priority: .userInitiated) {
                OutfitEngine.ranking(from: items, signals: signals, recentlyShown: history, seed: seed)
            }.value
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.rankTask = nil
            self.absorb(ranking, seed: seed)
        }
    }

    private func absorb(_ ranking: OutfitEngine.Ranking, seed: UInt64) {
        if ranking.outfits.isEmpty && everSeen.isEmpty {
            empty = true
            loading = false
            return
        }
        let ranking = OutfitEngine.Ranking(outfits: ranking.outfits.filter { !dropped.contains($0.id) }, complete: ranking.complete)
        var rng = SplitMix64(seed: seed)
        func shuffled(_ outfits: [Outfit], spread: Double) -> [Outfit] {
            outfits.map { o -> Outfit in var o = o; o.score += Double(rng.next() % 1000) / 1000 * spread; return o }
                .sorted { $0.score > $1.score }
        }

        let queued = Set(queue.map(\.id))
        let fresh = ranking.outfits.filter { !seenThisCycle.contains($0.id) && !queued.contains($0.id) }
        if !fresh.isEmpty {
            fruitlessRounds = 0
            queue += shuffled(fresh, spread: 0.8)
            fresh.forEach { seenThisCycle.insert($0.id) }
            for o in fresh where everSeen.insert(o.id).inserted { distinct += 1 }
        } else if ranking.complete || fruitlessRounds >= 3 {
            // Everything the closet makes has been shown: go round again, in a new order.
            fruitlessRounds = 0
            seenThisCycle = []
            if !(rounds.last?.entries.isEmpty ?? true) { rounds.append(Round(id: rounds.count)) }
            let again = shuffled(ranking.outfits, spread: 3)
            queue += again
            again.forEach { seenThisCycle.insert($0.id) }
        } else {
            fruitlessRounds += 1   // a big closet's sample came back with nothing new; try another
            refill()
            return
        }
        if waitingForPage { loadMore() }
        if queue.count < Self.pageSize * 3 && !ranking.complete { refill() }
    }

    // MARK: History

    private func remember(_ outfits: [Outfit]) {
        let now = Date.now
        outfits.forEach { history[$0.id] = now }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
            self.history = self.history.filter { $0.value > cutoff }
            UserDefaults.standard.set(self.history, forKey: Self.historyKey)
        }
    }
}
