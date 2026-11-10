import Foundation
import Observation
import Supabase

/// Signs in silently (anonymous Supabase user) and keeps the phone and the account in step:
/// items (+ photos and embeddings), outfit logs and wear events, purchase checks and the
/// style profile. A full sync pulls the account's copy first (merge rules in `SyncMerge.swift`),
/// then pushes this phone's. Every upsert is idempotent, so a sync can run any number of times.
///
/// Anonymous accounts live only as long as the app's keychain session. Saving the closet to an
/// email (a 6-digit code) makes it permanent, and the same email signs another phone in.
@MainActor
@Observable
final class Cloud {
    static let shared = Cloud()

    enum Status: Equatable {
        case notConfigured
        case signingIn
        case signedIn
        case anonymousDisabled
        case failed(String)

        var message: String {
            switch self {
            case .notConfigured: "Saved on this phone — Supabase isn't configured"
            case .signingIn: "Connecting…"
            case .signedIn: "Synced to your account"
            case .anonymousDisabled: "Turn on anonymous sign-ins in Supabase to sync and get ClosetWise's AI reads"
            case .failed(let why): "Offline — saved on this phone (\(why))"
            }
        }
    }

    private(set) var status: Status = SupabaseService.isConfigured ? .signingIn : .notConfigured
    private(set) var syncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    /// The email the closet is saved to; nil while the account is anonymous.
    private(set) var email: String?

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var isSignedIn: Bool { status == .signedIn }

    // MARK: Session

    /// Called at launch: sign in (or restore the session), then sync everything once.
    func start(_ store: ClosetStore) async {
        // Unit tests launch the app as their host; never touch the real project from a test run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard await ensureSession() != nil else { return }
        await sync(store, pull: true)
    }

    /// Back in the foreground: pick up anything changed on another phone.
    func refresh(_ store: ClosetStore) async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, isSignedIn else { return }
        await sync(store, pull: true)
    }

    /// Returns the signed-in user's id, signing in anonymously the first time.
    @discardableResult
    func ensureSession() async -> UUID? {
        guard let client = SupabaseService.client else { status = .notConfigured; return nil }
        if let session = try? await client.auth.session {
            status = .signedIn
            email = session.user.isAnonymous ? nil : session.user.email
            return session.user.id
        }
        status = .signingIn
        do {
            let session = try await client.auth.signInAnonymously()
            status = .signedIn
            email = nil
            return session.user.id
        } catch {
            let text = "\(error)".lowercased()
            status = text.contains("anonymous") ? .anonymousDisabled : .failed(Self.short(error))
            return nil
        }
    }

    // MARK: Sync

    /// Debounced sync after local changes.
    func scheduleSync(_ store: ClosetStore) {
        guard SupabaseService.isConfigured else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.sync(store)
        }
    }

    func sync(_ store: ClosetStore, pull: Bool = false) async {
        guard !syncing, let client = SupabaseService.client, let uid = await ensureSession() else { return }
        syncing = true
        defer { syncing = false }
        do {
            if pull { try await self.pull(store, client: client, uid: uid) }
            try await uploadPhotos(store, client: client, uid: uid)
            try await uploadOutfitPhotos(store, client: client, uid: uid)
            if !store.items.isEmpty {
                try await client.from("items").upsert(store.items.map { ItemRow($0, uid: uid, store: store) }, onConflict: "id", returning: .minimal).execute()
            }
            if !store.removedItemIDs.isEmpty {
                struct Archive: Encodable { let archived = true; let updated_at = Date.now }
                try await client.from("items").update(Archive()).in("id", values: store.removedItemIDs.map(\.uuidString)).execute()
            }

            struct Deleted: Encodable { let deleted = true; let updated_at = Date.now }
            if !store.removedLogIDs.isEmpty {
                try await client.from("outfits").update(Deleted()).in("id", values: store.removedLogIDs.map(\.uuidString)).execute()
            }
            if !store.removedCheckIDs.isEmpty {
                try await client.from("purchase_checks").update(Deleted()).in("id", values: store.removedCheckIDs.map(\.uuidString)).execute()
            }

            let logs = store.logs
            if !logs.isEmpty {
                try await client.from("outfits").upsert(logs.map { OutfitRow($0, uid: uid) }, onConflict: "id", returning: .minimal).execute()
                let known = Set(store.items.map(\.id))
                let events = logs.flatMap { log in log.itemIDs.filter(known.contains).map { WearEventRow(log: log, itemID: $0, uid: uid) } }
                try await client.from("wear_events").upsert(events, onConflict: "outfit_id,item_id", returning: .minimal).execute()
            }

            if !store.purchases.isEmpty {
                try await client.from("purchase_checks").upsert(store.purchases.map { PurchaseRow($0, uid: uid) }, onConflict: "id", returning: .minimal).execute()
            }

            try await client.from("style_profiles").upsert(StyleRow(store: store, uid: uid), onConflict: "user_id", returning: .minimal).execute()
            if !store.profile.name.isEmpty {
                struct Name: Encodable { let display_name: String }
                try await client.from("profiles").update(Name(display_name: store.profile.name)).eq("id", value: uid.uuidString).execute()
            }

            await embedNewPhotos(store, client: client)
            lastSync = .now
            lastError = nil
        } catch {
            lastError = Self.short(error)
        }
    }

    // MARK: Pull

    private func pull(_ store: ClosetStore, client: SupabaseClient, uid: UUID) async throws {
        let itemRows: [RemoteItemRow] = try await client.from("items")
            .select("id,name,category,kind,color,hex,material,fit,silhouette,style,formality,price,image_path,store,wear_count,last_worn,archived,updated_at")
            .execute().value
        let outfitRows: [RemoteOutfitRow] = try await client.from("outfits")
            .select("id,worn_on,reaction,source,photo_path,updated_at,deleted").execute().value
        let wearRows: [RemoteWearRow] = try await client.from("wear_events").select("outfit_id,item_id").execute().value
        let checkRows: [RemoteCheckRow] = try await client.from("purchase_checks")
            .select("id,product,verdict,style_score,result,decision,created_at,deleted").execute().value
        let styleRows: [RemoteStyleRow] = try await client.from("style_profiles")
            .select("preferences,summary,tags,fit_notes,updated_at").execute().value
        let profileRows: [RemoteProfileRow] = try await client.from("profiles").select("display_name").execute().value

        var piecesByOutfit: [UUID: [UUID]] = [:]
        for w in wearRows { if let outfit = w.outfit_id { piecesByOutfit[outfit, default: []].append(w.item_id) } }

        var remote = RemoteCloset()
        remote.items = itemRows.compactMap { $0.model }
        remote.logs = outfitRows.filter { !$0.deleted }.compactMap { $0.model(pieces: piecesByOutfit[$0.id] ?? []) }
        remote.purchases = checkRows.filter { !$0.deleted }.compactMap(\.model)
        remote.deletedLogIDs = Set(outfitRows.filter(\.deleted).map(\.id))
        remote.deletedCheckIDs = Set(checkRows.filter(\.deleted).map(\.id))
        if let style = styleRows.first {
            remote.preferences = style.preferences.value
            remote.styleUpdatedAt = style.updated_at
            if let summary = style.summary, !summary.isEmpty {
                remote.summary = GeminiStyleSummary(summary: summary, tags: style.tags ?? [], fitNotes: style.fit_notes ?? "", updatedAt: style.updated_at)
            }
        }
        remote.name = profileRows.first?.display_name

        store.merge(remote)
        await downloadMissingPhotos(store, client: client, uid: uid)
    }

    /// Photos taken on another phone: fetch any this phone doesn't have yet.
    private func downloadMissingPhotos(_ store: ClosetStore, client: SupabaseClient, uid: UUID) async {
        let folder = uid.uuidString.lowercased()
        let wanted = store.items.compactMap(\.photo).map { ("items", $0) } + store.logs.compactMap(\.photo).map { ("outfits", $0) }
        var fetched = 0
        for (bucket, name) in wanted {
            let url = ClosetStore.photoDirectory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path),
                  let data = try? await client.storage.from(bucket).download(path: "\(folder)/\(name)") else { continue }
            try? FileManager.default.createDirectory(at: ClosetStore.photoDirectory, withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil {
                uploaded.insert(name)
                fetched += 1
            }
        }
        if fetched > 0 { store.items = store.items }   // redraw tiles with the new photos
    }

    // MARK: Account (email code)

    enum AccountError: LocalizedError {
        case notConnected, message(String)
        var errorDescription: String? {
            switch self {
            case .notConnected: "ClosetWise can't reach your account right now. Check your connection and try again."
            case .message(let text): text
            }
        }
    }

    /// Step 1 of saving this closet to an email: Supabase emails a code to confirm the address.
    func sendSaveCode(to email: String) async throws {
        guard let client = SupabaseService.client, await ensureSession() != nil else { throw AccountError.notConnected }
        do { _ = try await client.auth.update(user: UserAttributes(email: email)) } catch { throw Self.friendly(error) }
    }

    /// Step 2: the code makes the account permanent. Same user id, so nothing needs to move.
    func confirmSaveCode(email: String, code: String, store: ClosetStore) async throws {
        guard let client = SupabaseService.client else { throw AccountError.notConnected }
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
            self.email = response.user.email ?? email
        } catch { throw Self.friendly(error) }
        await sync(store)
    }

    /// Signing in on another phone: Supabase emails a code (only to an existing account).
    func sendSignInCode(to email: String) async throws {
        guard let client = SupabaseService.client else { throw AccountError.notConnected }
        do { try await client.auth.signInWithOTP(email: email, shouldCreateUser: false) } catch { throw Self.friendly(error) }
    }

    /// Replaces this phone's closet with the account's.
    func confirmSignIn(email: String, code: String, store: ClosetStore) async throws {
        guard let client = SupabaseService.client else { throw AccountError.notConnected }
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            self.email = response.user.email ?? email
            status = .signedIn
        } catch { throw Self.friendly(error) }
        resetCaches()
        store.resetForNewAccount(onboarded: true)
        await sync(store, pull: true)
    }

    /// Signs out and starts over as a new, empty anonymous closet.
    func signOut(store: ClosetStore) async {
        pending?.cancel()
        if let client = SupabaseService.client { try? await client.auth.signOut() }
        email = nil
        resetCaches()
        store.resetForNewAccount(onboarded: false)
        lastSync = nil
        await ensureSession()
    }

    private func resetCaches() {
        defaults.removeObject(forKey: "cloud.uploadedPhotos")
        defaults.removeObject(forKey: "cloud.embeddedItems")
    }

    private static func friendly(_ error: Error) -> AccountError {
        let text = "\(error)".lowercased()
        if text.contains("expired") || text.contains("invalid") && text.contains("otp") || text.contains("token has expired") {
            return .message("That code didn't work. Check it, or send a new one.")
        }
        if text.contains("email_exists") || text.contains("already been registered") || text.contains("already registered") {
            return .message("That email already has a ClosetWise closet. Use \"I already have an account\" to sign in with it.")
        }
        if text.contains("signups not allowed") || text.contains("otp_disabled") || text.contains("user not found") {
            return .message("No ClosetWise closet uses that email yet.")
        }
        if text.contains("rate limit") || text.contains("over_email_send_rate_limit") || text.contains("security purposes") {
            return .message("Too many emails just now. Wait a minute, then try again.")
        }
        if text.contains("invalid") && text.contains("email") {
            return .message("That doesn't look like an email address.")
        }
        return .message(short(error))
    }

    // MARK: Photos & embeddings

    private var uploaded: Set<String> {
        get { Set(defaults.stringArray(forKey: "cloud.uploadedPhotos") ?? []) }
        set { defaults.set(Array(newValue), forKey: "cloud.uploadedPhotos") }
    }
    private var embedded: Set<String> {
        get { Set(defaults.stringArray(forKey: "cloud.embeddedItems") ?? []) }
        set { defaults.set(Array(newValue), forKey: "cloud.embeddedItems") }
    }

    private func uploadPhotos(_ store: ClosetStore, client: SupabaseClient, uid: UUID) async throws {
        for item in store.items {
            guard let name = item.photo, !uploaded.contains(name) else { continue }
            let url = ClosetStore.photoDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            try await client.storage.from("items").upload("\(uid.uuidString.lowercased())/\(name)", data: data,
                                                           options: FileOptions(contentType: "image/png", upsert: true))
            uploaded.insert(name)
        }
    }

    private func uploadOutfitPhotos(_ store: ClosetStore, client: SupabaseClient, uid: UUID) async throws {
        for log in store.logs {
            guard let name = log.photo, !uploaded.contains(name) else { continue }
            guard let data = try? Data(contentsOf: ClosetStore.photoDirectory.appendingPathComponent(name)) else { continue }
            try await client.storage.from("outfits").upload("\(uid.uuidString.lowercased())/\(name)", data: data,
                                                             options: FileOptions(contentType: "image/png", upsert: true))
            uploaded.insert(name)
        }
    }

    /// Gemini image embeddings for items with real photos, used for visual duplicate search (`match_items`).
    private func embedNewPhotos(_ store: ClosetStore, client: SupabaseClient) async {
        struct Request: Encodable { let action = "embed"; let image_base64: String; let mime_type = "image/jpeg" }
        struct Response: Decodable { let embedding: [Float]? }
        struct Update: Encodable { let embedding: [Float] }
        for item in store.items {
            guard let name = item.photo, !embedded.contains(item.id.uuidString),
                  let jpeg = ClosetStore.photo(name)?.resized(maxSide: 768).jpegData(compressionQuality: 0.8) else { continue }
            guard let response: Response = try? await client.functions.invoke(
                "gemini", options: FunctionInvokeOptions(body: Request(image_base64: jpeg.base64EncodedString()))),
                  let vector = response.embedding, vector.count == 768 else { continue }
            if (try? await client.from("items").update(Update(embedding: vector)).eq("id", value: item.id.uuidString).execute()) != nil {
                embedded.insert(item.id.uuidString)
            }
        }
    }

    private static func short(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        return String(text.prefix(120))
    }
}

// MARK: - Rows

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private struct ItemRow: Encodable {
    let id: UUID, user_id: UUID, name: String, image_path: String?
    let category: String, kind: String, color: String, hex: String, material: String
    let fit: String, silhouette: String?, style: String, formality: Int, price: Double?
    let source: String, store: String?, wear_count: Int, last_worn: String?
    let archived = false
    let updated_at: Date

    @MainActor init(_ i: WardrobeItem, uid: UUID, store s: ClosetStore) {
        id = i.id; user_id = uid; name = i.name
        image_path = i.photo.map { "\(uid.uuidString.lowercased())/\($0)" }
        category = i.category.rawValue; kind = i.kind.rawValue; color = i.color
        hex = String(format: "%06X", i.hex); material = i.material
        fit = i.fit.rawValue; silhouette = i.silhouette; style = i.style; formality = i.formality
        price = i.price.map { NSDecimalNumber(decimal: $0).doubleValue }
        source = s.purchases.contains { $0.product.id == i.id && $0.decision == .bought } ? "check" : "photo"
        store = i.store; wear_count = i.wearCount; last_worn = i.lastWorn.map(dayFormatter.string)
        updated_at = i.updatedAt ?? Date(timeIntervalSince1970: 0)
    }
}

private struct OutfitRow: Encodable {
    let id: UUID, user_id: UUID, worn_on: String, reaction: String?, source: String, worn: Bool, photo_path: String?
    let updated_at: Date
    init(_ log: OutfitLog, uid: UUID) {
        id = log.id; user_id = uid; worn_on = dayFormatter.string(from: log.date)
        updated_at = log.updatedAt ?? log.date
        photo_path = log.photo.map { "\(uid.uuidString.lowercased())/\($0)" }
        reaction = log.reaction?.rawValue; source = log.source.rawValue; worn = true
    }
}

private struct WearEventRow: Encodable {
    let user_id: UUID, outfit_id: UUID, item_id: UUID, worn_on: String, confirmed: Bool
    init(log: OutfitLog, itemID: UUID, uid: UUID) {
        user_id = uid; outfit_id = log.id; item_id = itemID; worn_on = dayFormatter.string(from: log.date); confirmed = true
    }
}

private struct PurchaseRow: Encodable {
    struct Summary: Encodable { let similar_count: Int; let outfit_count: Int }
    let id: UUID, user_id: UUID, product: WardrobeItem, verdict: String, style_score: Int
    let result: Summary, decision: String?, decided_at: Date?, created_at: Date, updated_at: Date
    init(_ r: PurchaseRecord, uid: UUID) {
        updated_at = r.date
        id = r.id; user_id = uid; product = r.product; verdict = r.verdict; style_score = r.styleScore
        result = Summary(similar_count: r.similarCount, outfit_count: r.outfitCount)
        decision = r.decision.map { $0 == .bought ? "bought" : "skipped" }
        decided_at = r.decision == nil ? nil : r.date; created_at = r.date
    }
}

private struct StyleRow: Encodable {
    let user_id: UUID
    let preferences: StylePreferences
    let learned: StyleContext.Learned
    let summary: String?, tags: [String], fit_notes: String?
    let updated_at: Date

    @MainActor init(store: ClosetStore, uid: UUID) {
        user_id = uid
        preferences = store.preferences
        learned = store.styleContext.learned
        summary = store.geminiSummary?.summary
        tags = store.geminiSummary?.tags ?? store.learned.tags
        fit_notes = store.geminiSummary?.fitNotes
        updated_at = store.styleUpdatedAt ?? Date(timeIntervalSince1970: 0)
    }
}

// MARK: - Pulled rows

private struct RemoteItemRow: Decodable {
    let id: UUID, name: String, category: String
    let kind: String?, color: String?, hex: String?, material: String?, fit: String?, silhouette: String?
    let style: String?, formality: Int?, price: Double?, image_path: String?, store: String?
    let wear_count: Int?, last_worn: String?, archived: Bool, updated_at: Date

    var model: RemoteCloset.Item? {
        guard let category = ItemCategory(rawValue: category) else { return nil }
        let kind = kind.flatMap(GarmentKind.init(rawValue:)) ?? AttributeGuesser.defaultKind(for: category)
        var item = WardrobeItem(id: id, name: name, category: category, kind: kind, color: color ?? "black",
                                hex: hex.flatMap { UInt32($0, radix: 16) } ?? 0x8A8F94, material: material ?? "",
                                fit: fit.flatMap(FitType.init(rawValue:)) ?? .regular, silhouette: silhouette,
                                style: style ?? "casual", formality: formality ?? 2,
                                price: price.map { Decimal($0) }, wearCount: wear_count ?? 0,
                                photo: image_path.map { ($0 as NSString).lastPathComponent }, store: store)
        item.lastWorn = last_worn.flatMap(dayFormatter.date(from:))
        return RemoteCloset.Item(item: item, archived: archived, updatedAt: updated_at)
    }
}

private struct RemoteOutfitRow: Decodable {
    let id: UUID, worn_on: String, reaction: String?, source: String?, photo_path: String?, updated_at: Date, deleted: Bool

    func model(pieces: [UUID]) -> OutfitLog? {
        guard let day = dayFormatter.date(from: worn_on) else { return nil }
        // Noon on the day worn, so the date doesn't slip across time zones.
        let date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return OutfitLog(id: id, date: date, itemIDs: pieces,
                         reaction: reaction.flatMap(OutfitLog.Reaction.init(rawValue:)),
                         source: source.flatMap(OutfitLog.Source.init(rawValue:)) ?? .logged,
                         photo: photo_path.map { ($0 as NSString).lastPathComponent }, updatedAt: updated_at)
    }
}

private struct RemoteWearRow: Decodable { let outfit_id: UUID?; let item_id: UUID }

private struct RemoteCheckRow: Decodable {
    struct Summary: Decodable { let similar_count: Int?; let outfit_count: Int? }
    let id: UUID, product: Lenient<WardrobeItem>, verdict: String?, style_score: Int?
    let result: Lenient<Summary>?, decision: String?, created_at: Date, deleted: Bool

    var model: PurchaseRecord? {
        guard let product = product.value else { return nil }
        return PurchaseRecord(id: id, date: created_at, product: product, verdict: verdict ?? "Consider",
                              styleScore: style_score ?? 0, similarCount: result?.value?.similar_count ?? 0,
                              outfitCount: result?.value?.outfit_count ?? 0,
                              decision: decision == "bought" ? .bought : decision == "skipped" ? .skipped : nil)
    }
}

private struct RemoteStyleRow: Decodable {
    let preferences: Lenient<StylePreferences>, summary: String?, tags: [String]?, fit_notes: String?, updated_at: Date
}

private struct RemoteProfileRow: Decodable { let display_name: String? }

/// Decodes a JSON value if it has the expected shape, and nil otherwise (e.g. an empty `{}` default).
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
