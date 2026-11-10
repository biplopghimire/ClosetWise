import Foundation

/// What the account holds in Supabase, already turned into app models.
struct RemoteCloset {
    struct Item {
        var item: WardrobeItem
        var archived: Bool
        var updatedAt: Date
    }

    var items: [Item] = []
    var logs: [OutfitLog] = []
    var purchases: [PurchaseRecord] = []
    /// Outfits and checks deleted on another phone.
    var deletedLogIDs: Set<UUID> = []
    var deletedCheckIDs: Set<UUID> = []
    var preferences: StylePreferences?
    var styleUpdatedAt: Date?
    var summary: GeminiStyleSummary?
    var name: String?

    var isEmpty: Bool { items.isEmpty && logs.isEmpty && purchases.isEmpty }
}

/// Folds the account's copy into this phone's.
///
/// Rules:
/// - Items: the newer copy wins (by `updatedAt`). Wear counts and last-worn take the higher of the
///   two, so a wear logged on either phone is never lost to an older edit. An item archived in the
///   account leaves this phone unless it was edited here afterwards. Items removed on this phone stay removed.
/// - Outfits and purchase checks are added if this phone doesn't have them (they're never edited),
///   and dropped if they were deleted on another phone. Ones deleted here aren't brought back.
/// - Stated style: the newer copy wins. ClosetWise's written summary: the newer one wins.
/// - Name: filled in if this phone has none.
extension ClosetStore {
    @discardableResult
    func merge(_ remote: RemoteCloset) -> Bool {
        applyingRemote = true
        defer { applyingRemote = false }
        var changed = false
        let epoch = Date(timeIntervalSince1970: 0)

        for r in remote.items {
            let index = items.firstIndex { $0.id == r.item.id }
            if r.archived {
                if let index, (items[index].updatedAt ?? epoch) <= r.updatedAt {
                    items.remove(at: index)
                    changed = true
                }
                continue
            }
            if removedItemIDs.contains(r.item.id) { continue }
            guard let index else {
                var item = r.item
                item.updatedAt = r.updatedAt
                items.append(item)
                changed = true
                continue
            }
            let local = items[index]
            var merged = (local.updatedAt ?? epoch) < r.updatedAt ? r.item : local
            if merged.photo == nil { merged.photo = local.photo }
            merged.updatedAt = max(local.updatedAt ?? epoch, r.updatedAt)
            merged.wearCount = max(local.wearCount, r.item.wearCount)
            merged.lastWorn = [local.lastWorn, r.item.lastWorn].compactMap { $0 }.max()
            if merged != local {
                items[index] = merged
                changed = true
            }
        }

        if logs.contains(where: { remote.deletedLogIDs.contains($0.id) }) {
            logs.removeAll { remote.deletedLogIDs.contains($0.id) }
            changed = true
        }
        if purchases.contains(where: { remote.deletedCheckIDs.contains($0.id) }) {
            purchases.removeAll { remote.deletedCheckIDs.contains($0.id) }
            changed = true
        }

        let knownLogs = Set(logs.map(\.id)).union(removedLogIDs).union(remote.deletedLogIDs)
        let newLogs = remote.logs.filter { !knownLogs.contains($0.id) }
        if !newLogs.isEmpty {
            logs = (logs + newLogs).sorted { $0.date < $1.date }
            for log in newLogs where log.reaction == .loved { lovedCombos.insert(Outfit.comboKey(log.itemIDs)) }
            changed = true
        }

        let knownChecks = Set(purchases.map(\.id)).union(removedCheckIDs).union(remote.deletedCheckIDs)
        let newChecks = remote.purchases.filter { !knownChecks.contains($0.id) }
        if !newChecks.isEmpty {
            purchases = (purchases + newChecks).sorted { $0.date > $1.date }
            changed = true
        }

        if let prefs = remote.preferences, let stamp = remote.styleUpdatedAt,
           stamp > (styleUpdatedAt ?? .distantPast), prefs != preferences {
            // Inspiration photos live on the phone that took them; keep this phone's.
            var incoming = prefs
            incoming.inspirationFiles = preferences.inspirationFiles
            preferences = incoming
            styleUpdatedAt = stamp
            changed = true
        }

        if let summary = remote.summary, summary.updatedAt > (geminiSummary?.updatedAt ?? .distantPast) {
            geminiSummary = summary
            changed = true
        }

        if profile.name.isEmpty, let name = remote.name, !name.isEmpty {
            profile.name = name
            changed = true
        }
        // A closet restored from the account doesn't need the welcome screens.
        if !profile.onboarded, !remote.isEmpty {
            profile.onboarded = true
            changed = true
        }

        if changed { saveLocally() }
        return changed
    }

    /// Empties this phone before it switches to a different account (or signs out).
    func resetForNewAccount(onboarded: Bool) {
        applyingRemote = true
        defer { applyingRemote = false }
        items = []
        logs = []
        purchases = []
        removedItemIDs = []
        removedLogIDs = []
        removedCheckIDs = []
        dislikedCombos = []
        lovedCombos = []
        preferences = StylePreferences()
        styleUpdatedAt = nil
        geminiSummary = nil
        profile = UserProfile(name: "", onboarded: onboarded)
        saveLocally()
    }
}
