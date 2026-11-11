import XCTest
@testable import ClosetWise

final class SyncMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }
    private var t2: Date { t0.addingTimeInterval(120) }

    private func tee(_ name: String = "Black tee", wears: Int = 3, updated: Date? = nil, id: UUID = UUID()) -> WardrobeItem {
        var item = WardrobeItem(id: id, name: name, category: .top, kind: .tee, color: "black", hex: 0x1D1D1F,
                                material: "cotton", fit: .regular, style: "casual", wearCount: wears)
        item.updatedAt = updated
        return item
    }

    private func store(_ items: [WardrobeItem] = [], logs: [OutfitLog] = []) -> ClosetStore {
        ClosetStore(items: items, logs: logs, profile: UserProfile(name: "", onboarded: true), persist: false)
    }

    func testNewRemoteItemIsAdded() {
        let s = store()
        let changed = s.merge(RemoteCloset(items: [.init(item: tee(), archived: false, updatedAt: t1)]))
        XCTAssertTrue(changed)
        XCTAssertEqual(s.items.count, 1)
        XCTAssertEqual(s.items[0].updatedAt, t1)
    }

    func testNewerRemoteEditWins() {
        let id = UUID()
        let s = store([tee("Black tee", updated: t0, id: id)])
        s.merge(RemoteCloset(items: [.init(item: tee("Black boxy tee", id: id), archived: false, updatedAt: t1)]))
        XCTAssertEqual(s.items[0].name, "Black boxy tee")
    }

    func testNewerLocalEditWins() {
        let id = UUID()
        let s = store([tee("Mine", updated: t2, id: id)])
        s.merge(RemoteCloset(items: [.init(item: tee("Theirs", id: id), archived: false, updatedAt: t1)]))
        XCTAssertEqual(s.items[0].name, "Mine")
    }

    func testWearCountsNeverGoBackwards() {
        let id = UUID()
        // The remote edit is newer but was made before this phone logged two more wears.
        let s = store([tee(wears: 7, updated: t0, id: id)])
        s.merge(RemoteCloset(items: [.init(item: tee("Renamed", wears: 5, id: id), archived: false, updatedAt: t1)]))
        XCTAssertEqual(s.items[0].name, "Renamed")
        XCTAssertEqual(s.items[0].wearCount, 7)
    }

    func testArchivedRemotelyIsRemovedUnlessEditedHereSince() {
        let gone = UUID(), kept = UUID()
        let s = store([tee(updated: t0, id: gone), tee(updated: t2, id: kept)])
        s.merge(RemoteCloset(items: [
            .init(item: tee(id: gone), archived: true, updatedAt: t1),
            .init(item: tee(id: kept), archived: true, updatedAt: t1),
        ]))
        XCTAssertEqual(s.items.map(\.id), [kept])
    }

    func testRemovedHereStaysRemoved() {
        let id = UUID()
        let s = store()
        s.removedItemIDs = [id]
        s.merge(RemoteCloset(items: [.init(item: tee(id: id), archived: false, updatedAt: t2)]))
        XCTAssertTrue(s.items.isEmpty)
    }

    func testLocalPhotoIsKeptWhenRemoteHasNone() {
        let id = UUID()
        var local = tee(updated: t0, id: id)
        local.photo = "item-1.png"
        let s = store([local])
        s.merge(RemoteCloset(items: [.init(item: tee("New name", id: id), archived: false, updatedAt: t1)]))
        XCTAssertEqual(s.items[0].photo, "item-1.png")
    }

    func testOutfitsAndChecksAreUnionedOnce() {
        let shared = OutfitLog(date: t0, itemIDs: [])
        let s = store(logs: [shared])
        let remoteLog = OutfitLog(date: t1, itemIDs: [UUID()], reaction: .loved)
        let check = PurchaseRecord(product: tee(), verdict: "Skip", styleScore: 50, similarCount: 2, outfitCount: 1, decision: .skipped)
        let remote = RemoteCloset(logs: [shared, remoteLog], purchases: [check])
        XCTAssertTrue(s.merge(remote))
        XCTAssertEqual(s.logs.count, 2)
        XCTAssertEqual(s.purchases.count, 1)
        XCTAssertEqual(s.lovedCombos.count, 1)
        XCTAssertFalse(s.merge(remote), "a second pull of the same data changes nothing")
    }

    func testNewerStatedStyleWinsButInspirationPhotosStayLocal() {
        let s = store()
        s.preferences.inspirationFiles = ["insp-1.png"]
        s.styleUpdatedAt = t0
        var prefs = StylePreferences()
        prefs.vibes = ["Minimal", "Scandi"]
        prefs.inspirationFiles = ["insp-elsewhere.png"]
        s.merge(RemoteCloset(preferences: prefs, styleUpdatedAt: t1))
        XCTAssertEqual(s.preferences.vibes, ["Minimal", "Scandi"])
        XCTAssertEqual(s.preferences.inspirationFiles, ["insp-1.png"])
        XCTAssertEqual(s.styleUpdatedAt, t1, "pulled style isn't re-stamped as a local edit")
    }

    func testRestoredClosetSkipsWelcomeAndFillsName() {
        let s = ClosetStore(items: [], logs: [], persist: false)
        s.merge(RemoteCloset(items: [.init(item: tee(), archived: false, updatedAt: t1)], name: "Alex"))
        XCTAssertTrue(s.profile.onboarded)
        XCTAssertEqual(s.profile.name, "Alex")
    }

    func testLocalEditsAreStamped() {
        let s = store([tee()])
        var item = s.items[0]
        item.name = "Edited"
        s.updateItem(item)
        XCTAssertNotNil(s.items[0].updatedAt)
        s.logOutfit([item.id], reaction: nil)
        XCTAssertNotNil(s.logs.last?.updatedAt)
        s.preferences.vibes = ["Edgy"]
        XCTAssertNotNil(s.styleUpdatedAt)
    }

    func testOutfitsDeletedElsewhereAreDroppedAndDeletedHereStayGone() {
        let deletedThere = OutfitLog(date: t0, itemIDs: [])
        let deletedHere = OutfitLog(date: t1, itemIDs: [])
        let s = store(logs: [deletedThere])
        s.removedLogIDs = [deletedHere.id]
        var remote = RemoteCloset(logs: [deletedHere])
        remote.deletedLogIDs = [deletedThere.id]
        s.merge(remote)
        XCTAssertTrue(s.logs.isEmpty)
    }

    func testClearingMarksOutfitsAndChecksForDeletion() {
        let check = PurchaseRecord(product: tee(), verdict: "Skip", styleScore: 50, similarCount: 2, outfitCount: 1, decision: .skipped)
        let s = ClosetStore(items: [tee()], logs: [OutfitLog(date: t0, itemIDs: [])], purchases: [check], persist: false)
        s.clearCloset()
        XCTAssertEqual(s.removedLogIDs.count, 1)
        XCTAssertEqual(s.removedCheckIDs, [check.id])
    }

    func testDemoLoadsWithStableIDs() {
        XCTAssertEqual(SampleData.outfitLogs.map(\.id), SampleData.outfitLogs.map(\.id))
        XCTAssertEqual(Set(SampleData.outfitLogs.map(\.id)).count, SampleData.outfitLogs.count)
        XCTAssertTrue(SampleData.outfitLogs.allSatisfy { $0.id.uuidString.hasPrefix("00000000-0000-0000-0000-") })
        XCTAssertTrue(SampleData.purchaseHistory.allSatisfy { $0.id.uuidString.hasPrefix("00000000-0000-0000-0000-") })
    }

    func testRemovingDemoKeepsYourOwnPieces() {
        // An older closet: demo loaded with the plain sample ids, plus real pieces added on top.
        var mine = tee()
        mine.photo = "my-tee.png"
        let check = PurchaseRecord(product: tee(), verdict: "Skip", styleScore: 50, similarCount: 2, outfitCount: 1, decision: .skipped)
        let mixedLog = OutfitLog(date: t0, itemIDs: [mine.id, SampleData.wideLegJeans.id])
        let store = ClosetStore(items: [mine], logs: [mixedLog], purchases: [check], persist: false)
        store.loadDemo(account: nil)
        let photographed = store.items.firstIndex { $0.id == SampleData.loafers.id }!
        store.items[photographed].photo = "my-loafers.png"   // a demo piece you gave a real photo
        XCTAssertTrue(store.hasDemoData)

        store.removeDemo()

        XCTAssertEqual(store.items.map(\.id), [mine.id, SampleData.loafers.id], "your pieces and photographed ones stay")
        XCTAssertEqual(store.logs.map(\.id), [mixedLog.id], "your outfit stays")
        XCTAssertEqual(store.logs.first?.itemIDs, [mine.id], "…without the demo jeans")
        XCTAssertEqual(store.purchases.map(\.id), [check.id])
        XCTAssertFalse(store.hasDemoData)
        XCTAssertEqual(store.removedItemIDs, Set(SampleData.wardrobe.map(\.id)).subtracting([SampleData.loafers.id]),
                       "the other demo pieces are deleted on sync too")
        XCTAssertEqual(store.removedLogIDs, Set(SampleData.outfitLogs.map(\.id)))
        XCTAssertEqual(store.removedCheckIDs, Set(SampleData.purchaseHistory.map(\.id)))
    }

    func testDemoIDsAreStablePerAccountAndDistinctAcrossAccounts() {
        let alice = UUID(), bob = UUID()
        let a1 = SampleData.demo(for: alice), a2 = SampleData.demo(for: alice), b = SampleData.demo(for: bob)

        // Same account: loading again (or on another phone) gives the same rows.
        XCTAssertEqual(a1.items.map(\.id), a2.items.map(\.id))
        XCTAssertEqual(a1.logs.map(\.id), a2.logs.map(\.id))
        XCTAssertEqual(a1.purchases.map(\.id), a2.purchases.map(\.id))

        // Two accounts on one project never share a row id.
        let aliceIDs = Set(a1.items.map(\.id) + a1.logs.map(\.id) + a1.purchases.map(\.id))
        let bobIDs = Set(b.items.map(\.id) + b.logs.map(\.id) + b.purchases.map(\.id))
        XCTAssertTrue(aliceIDs.isDisjoint(with: bobIDs))
        XCTAssertTrue(aliceIDs.isDisjoint(with: Set(SampleData.wardrobe.map(\.id))))

        // Outfits still point at that account's demo items, and they're recognised as demo.
        let itemIDs = Set(a1.items.map(\.id))
        XCTAssertTrue(a1.logs.allSatisfy { $0.itemIDs.allSatisfy(itemIDs.contains) })
        XCTAssertTrue(a1.items.allSatisfy { SampleData.isDemoItem($0.id) })
        XCTAssertFalse(SampleData.isDemoItem(UUID()))

        // No account (Supabase not set up): the plain sample ids.
        XCTAssertEqual(SampleData.demo(for: nil).items.map(\.id), SampleData.wardrobe.map(\.id))

        let store = ClosetStore(items: [], logs: [], purchases: [], persist: false)
        store.loadDemo(account: alice)
        store.loadDemo(account: alice)
        XCTAssertEqual(store.items.count, SampleData.wardrobe.count, "loading twice doesn't duplicate")
        XCTAssertTrue(store.hasDemoItems && store.hasOnlyDemoItems)
    }
}
