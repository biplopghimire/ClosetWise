import Foundation
import Observation
import UIKit

/// App state: the closet, outfit history and style profile.
/// Saved to a local JSON file for now; Supabase sync replaces this in Phase 1.
@Observable
final class ClosetStore {
    var items: [WardrobeItem]
    var logs: [OutfitLog]
    var preferences: StylePreferences {
        didSet { if !applyingRemote { styleUpdatedAt = .now } }
    }
    /// When the user last changed their stated style (sync keeps the newer copy).
    var styleUpdatedAt: Date?
    var geminiSummary: GeminiStyleSummary?
    var dislikedCombos: Set<String>
    var lovedCombos: Set<String>
    var purchases: [PurchaseRecord]
    var profile: UserProfile
    /// Items removed from the closet; synced as archived so the history stays intact.
    var removedItemIDs: Set<UUID>
    /// Outfits and checks deleted here; synced as deleted so other phones drop them too.
    var removedLogIDs: Set<UUID> = []
    var removedCheckIDs: Set<UUID> = []

    /// Today's weather where the user is (not saved or synced; set by `WeatherService`).
    var weather: WeatherNow?

    @ObservationIgnored private let persist: Bool
    /// True while sync is writing the account's copy in, so it isn't stamped as a local edit.
    @ObservationIgnored var applyingRemote = false

    private struct Snapshot: Codable {
        var items: [WardrobeItem]
        var logs: [OutfitLog]
        var preferences: StylePreferences
        var geminiSummary: GeminiStyleSummary?
        var dislikedCombos: Set<String>
        var lovedCombos: Set<String>
        var purchases: [PurchaseRecord]?
        var profile: UserProfile?
        var removedItemIDs: Set<UUID>?
        var styleUpdatedAt: Date?
        var removedLogIDs: Set<UUID>?
        var removedCheckIDs: Set<UUID>?
    }

    init(items: [WardrobeItem], logs: [OutfitLog], preferences: StylePreferences = .init(),
         geminiSummary: GeminiStyleSummary? = nil, dislikedCombos: Set<String> = [], lovedCombos: Set<String> = [],
         purchases: [PurchaseRecord] = [], profile: UserProfile = .init(), removedItemIDs: Set<UUID> = [],
         styleUpdatedAt: Date? = nil, persist: Bool) {
        self.items = items
        self.logs = logs
        self.preferences = preferences
        self.geminiSummary = geminiSummary
        self.dislikedCombos = dislikedCombos
        self.lovedCombos = lovedCombos
        self.purchases = purchases
        self.profile = profile
        self.removedItemIDs = removedItemIDs
        self.styleUpdatedAt = styleUpdatedAt
        self.persist = persist
    }

    static func load() -> ClosetStore {
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            let store = ClosetStore(items: s.items, logs: s.logs, preferences: s.preferences, geminiSummary: s.geminiSummary,
                               dislikedCombos: s.dislikedCombos, lovedCombos: s.lovedCombos,
                               purchases: s.purchases ?? [],
                               // Closets saved before profiles existed have already been set up.
                               profile: s.profile ?? UserProfile(name: "", onboarded: !s.items.isEmpty),
                               removedItemIDs: s.removedItemIDs ?? [], styleUpdatedAt: s.styleUpdatedAt, persist: true)
            store.removedLogIDs = s.removedLogIDs ?? []
            store.removedCheckIDs = s.removedCheckIDs ?? []
            return store
        }
        // New install: an empty closet; the welcome screen offers a demo closet.
        return ClosetStore(items: [], logs: [], persist: true)
    }

    static let preview = ClosetStore(items: SampleData.wardrobe, logs: SampleData.outfitLogs, purchases: SampleData.purchaseHistory,
                                     profile: UserProfile(name: "Jamie", onboarded: true), persist: false)

    /// Fills the closet with the sample wardrobe, outfit history and checks (for demos).
    /// Adds the demo closet with ids made for `account` (see `SampleData.demo(for:)`).
    func loadDemo(account: UUID?) {
        let demo = SampleData.demo(for: account)
        let existing = Set(items.map(\.id))
        items += demo.items.filter { !existing.contains($0.id) }
        logs += demo.logs.filter { log in !logs.contains { $0.id == log.id } }
        purchases += demo.purchases.filter { r in !purchases.contains { $0.id == r.id } }
        removedItemIDs.subtract(demo.items.map(\.id))
        removedLogIDs.subtract(demo.logs.map(\.id))
        removedCheckIDs.subtract(demo.purchases.map(\.id))
        save()
    }

    /// Removes every item, outfit and check (the account and style preferences stay).
    func clearCloset() {
        removedItemIDs.formUnion(items.map(\.id))
        removedLogIDs.formUnion(logs.map(\.id))
        removedCheckIDs.formUnion(purchases.map(\.id))
        items = []
        logs = []
        purchases = []
        dislikedCombos = []
        lovedCombos = []
        geminiSummary = nil
        save()
    }

    /// Removes only the demo closet: its pieces, outfits and checks. Pieces you added yourself
    /// (and any demo piece you gave a real photo), and outfits and checks you logged, stay;
    /// your outfits just lose any removed demo pieces. Removals sync like any other delete.
    func removeDemo() {
        let demoItems = Set(items.filter { SampleData.isDemoItem($0.id) && $0.photo == nil }.map(\.id))
        let demoLogs = logs.filter { SampleData.isDemoLog($0.id) }.map(\.id)
        let demoChecks = purchases.filter { SampleData.isDemoCheck($0.id) }.map(\.id)
        items.removeAll { demoItems.contains($0.id) }
        logs.removeAll { SampleData.isDemoLog($0.id) }
        purchases.removeAll { SampleData.isDemoCheck($0.id) }
        for i in logs.indices where logs[i].itemIDs.contains(where: demoItems.contains) {
            logs[i].itemIDs.removeAll(where: demoItems.contains)
            logs[i].updatedAt = .now
        }
        removedItemIDs.formUnion(demoItems)
        removedLogIDs.formUnion(demoLogs)
        removedCheckIDs.formUnion(demoChecks)
        save()
    }

    var hasDemoItems: Bool { items.contains { SampleData.isDemoItem($0.id) } }
    /// Any demo piece, outfit or check left in the closet.
    var hasDemoData: Bool {
        items.contains { SampleData.isDemoItem($0.id) && $0.photo == nil } || logs.contains { SampleData.isDemoLog($0.id) } || purchases.contains { SampleData.isDemoCheck($0.id) }
    }

    func save() {
        guard persist else { return }
        let snapshot = Snapshot(items: items, logs: logs, preferences: preferences, geminiSummary: geminiSummary,
                                dislikedCombos: dislikedCombos, lovedCombos: lovedCombos, purchases: purchases,
                                profile: profile, removedItemIDs: removedItemIDs, styleUpdatedAt: styleUpdatedAt,
                                removedLogIDs: removedLogIDs, removedCheckIDs: removedCheckIDs)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: Self.fileURL, options: .atomic)
        Task { @MainActor in Cloud.shared.scheduleSync(self) }
    }

    /// Writes to disk without scheduling an upload (used after pulling the account's copy).
    func saveLocally() {
        guard persist else { return }
        let snapshot = Snapshot(items: items, logs: logs, preferences: preferences, geminiSummary: geminiSummary,
                                dislikedCombos: dislikedCombos, lovedCombos: lovedCombos, purchases: purchases,
                                profile: profile, removedItemIDs: removedItemIDs, styleUpdatedAt: styleUpdatedAt,
                                removedLogIDs: removedLogIDs, removedCheckIDs: removedCheckIDs)
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Derived

    var learned: LearnedStyle { StyleLearner.learn(items: items, logs: logs) }

    var styleContext: StyleContext { StyleContext(preferences: preferences, learned: learned) }

    /// Explicit vibes first, then what we've noticed.
    var styleTags: [String] {
        var seen = Set<String>()
        return (preferences.vibes + (geminiSummary?.tags ?? learned.tags)).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Today's ideas. Seeded by the day, so Home shows a different strong outfit each day
    /// (and the same one all day) instead of always the single top scorer.
    func suggestions(limit: Int = 6) -> [Outfit] {
        let day = UInt64(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0)
        return OutfitEngine.suggest(from: items, signals: outfitSignals, limit: limit, seed: day)
    }

    func outfits(with item: WardrobeItem) -> [Outfit] {
        OutfitEngine.outfits(with: item, from: items, signals: outfitSignals)
    }

    /// Taste plus today's weather — for what to wear now. Purchase checks use `signals`
    /// (no weather), so a coat isn't judged on a summer afternoon.
    var outfitSignals: StyleSignals {
        var s = signals
        s.weather = weather
        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        s.recentlyWorn = Set(logs.filter { $0.date > weekAgo }.map { Outfit.comboKey($0.itemIDs) })
        return s
    }

    var signals: StyleSignals {
        StyleSignals(preferences: preferences, learned: learned, disliked: dislikedCombos, loved: lovedCombos)
    }

    func item(_ id: UUID) -> WardrobeItem? { items.first { $0.id == id } }

    func logs(onSameWeekAs date: Date = .now) -> [OutfitLog] {
        let cal = Calendar.current
        return logs.filter { cal.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
    }

    // MARK: Actions

    /// Logs an outfit: bumps wear counts, stamps last-worn, and feeds the style profile.
    @discardableResult
    func logOutfit(_ itemIDs: [UUID], reaction: OutfitLog.Reaction?, source: OutfitLog.Source = .logged, date: Date = .now, photo: String? = nil) -> OutfitLog {
        let log = OutfitLog(date: date, itemIDs: itemIDs, reaction: reaction, source: source, photo: photo, updatedAt: .now)
        logs.append(log)
        for id in itemIDs {
            guard let i = items.firstIndex(where: { $0.id == id }) else { continue }
            items[i].wearCount += 1
            items[i].lastWorn = max(items[i].lastWorn ?? date, date)
            items[i].updatedAt = .now
        }
        if reaction == .loved { lovedCombos.insert(Outfit.comboKey(itemIDs)) }
        save()
        return log
    }

    func react(to outfit: Outfit, _ reaction: OutfitLog.Reaction) {
        let key = Outfit.comboKey(outfit.pieces.map(\.id))
        switch reaction {
        case .loved: lovedCombos.insert(key); dislikedCombos.remove(key)
        case .notMe: dislikedCombos.insert(key); lovedCombos.remove(key)
        case .fine: break
        }
        save()
    }

    func updateItem(_ item: WardrobeItem) {
        var item = item
        item.updatedAt = .now
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        removedItemIDs.remove(item.id)
        save()
    }

    func removeItem(_ item: WardrobeItem) {
        items.removeAll { $0.id == item.id }
        removedItemIDs.insert(item.id)
        save()
    }

    // MARK: Purchase checks

    func check(_ product: WardrobeItem) -> PurchaseCheckResult {
        PurchaseCheckEngine.check(product, closet: items, signals: signals)
    }

    /// Saves the check with the user's decision; buying adds the piece to the closet.
    func record(_ result: PurchaseCheckResult, decision: PurchaseRecord.Decision?) {
        purchases.insert(PurchaseRecord(product: result.product, verdict: result.verdict.rawValue,
                                        styleScore: result.styleFit.score, similarCount: result.duplicates.count,
                                        outfitCount: result.outfits.count, decision: decision), at: 0)
        if decision == .bought, !items.contains(where: { $0.id == result.product.id }) {
            var item = result.product
            item.wearCount = 0
            item.lastWorn = nil
            item.updatedAt = .now
            items.append(item)
        }
        save()
    }

    var checksThisMonth: Int {
        purchases.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.count
    }

    var savedBySkipping: Decimal {
        purchases.filter { $0.decision == .skipped }.compactMap(\.product.price).reduce(0, +)
    }

    // MARK: Item photos

    /// Stores a product/garment photo and returns its file name.
    func savePhoto(_ image: UIImage) -> String? {
        guard let png = image.resized(maxSide: 1024).pngData() else { return nil }
        let name = "item-\(UUID().uuidString).png"
        try? FileManager.default.createDirectory(at: Self.photoDirectory, withIntermediateDirectories: true)
        guard (try? png.write(to: Self.photoDirectory.appendingPathComponent(name))) != nil else { return nil }
        return name
    }

    private static let photoCache = NSCache<NSString, UIImage>()

    static func photo(_ name: String) -> UIImage? {
        if let hit = photoCache.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: photoDirectory.appendingPathComponent(name).path) else { return nil }
        photoCache.setObject(image, forKey: name as NSString)
        return image
    }

    private static var cutoutFlags: [String: Bool] = [:]

    /// True when the photo is a cut-out (background removed, transparent corners) rather than a
    /// photo with its background still in it. Checked once per photo.
    static func isCutout(_ name: String) -> Bool {
        if let known = cutoutFlags[name] { return known }
        let result = photo(name).map(hasTransparentCorners) ?? false
        cutoutFlags[name] = result
        return result
    }

    private static func hasTransparentCorners(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        let corners = [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)]
        let clear = corners.filter { pixels[($0.1 * side + $0.0) * 4 + 3] < 24 }.count
        return clear >= 2
    }

    // MARK: Inspiration photos

    func addInspiration(_ data: Data) {
        guard let image = UIImage(data: data), let jpeg = image.resized(maxSide: 1024).jpegData(compressionQuality: 0.8) else { return }
        let name = "inspo-\(UUID().uuidString).jpg"
        try? FileManager.default.createDirectory(at: Self.inspirationDirectory, withIntermediateDirectories: true)
        guard (try? jpeg.write(to: Self.inspirationDirectory.appendingPathComponent(name))) != nil else { return }
        preferences.inspirationFiles.append(name)
        save()
    }

    func removeInspiration(_ name: String) {
        try? FileManager.default.removeItem(at: Self.inspirationDirectory.appendingPathComponent(name))
        preferences.inspirationFiles.removeAll { $0 == name }
        save()
    }

    func inspirationImage(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: Self.inspirationDirectory.appendingPathComponent(name).path)
    }

    // MARK: Files

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClosetWise")
    }
    private static var fileURL: URL { directory.appendingPathComponent("closet.json") }
    static var inspirationDirectory: URL { directory.appendingPathComponent("inspiration") }
    static var photoDirectory: URL { directory.appendingPathComponent("photos") }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
