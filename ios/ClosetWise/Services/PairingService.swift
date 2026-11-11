import Foundation
import Supabase

/// Asks Gemini which of the user's own pieces go best with the ones they locked in the Outfits tab.
enum PairingService {
    struct Piece: Encodable {
        let id: String, name: String, category: String, color: String, fit: String
        let silhouette: String?, style: String, formality: Int

        init(_ item: WardrobeItem) {
            id = item.id.uuidString
            name = item.name
            category = item.category.rawValue
            color = item.color
            fit = item.fit.rawValue
            silhouette = item.silhouette
            style = item.style
            formality = item.formality
        }
    }

    struct Result {
        /// Best first, per slot.
        var picks: [OutfitSlot: [UUID]]
        var note: String
    }

    enum PairingError: Error { case unavailable }

    private struct Request: Encodable {
        let action = "pair_pieces"
        let locked: [Piece]
        let candidates: [String: [Piece]]
        let profile: StyleContext
    }

    private struct Response: Decodable {
        struct Pick: Decodable { let slot: String; let item_ids: [String] }
        let picks: [Pick]
        let note: String
    }

    /// Gemini's picks for each unlocked slot. Throws `unavailable` without a backend or a Gemini key.
    static func picks(locked: [WardrobeItem], candidates: [OutfitSlot: [WardrobeItem]], profile: StyleContext) async throws -> Result {
        guard let client = SupabaseService.client, GeminiKey.current != nil, !locked.isEmpty else { throw PairingError.unavailable }
        // Keep the request small: the best dozen per slot is plenty to choose from.
        let request = Request(
            locked: locked.map(Piece.init),
            candidates: Dictionary(uniqueKeysWithValues: candidates.map { ($0.key.rawValue, $0.value.prefix(12).map(Piece.init)) }),
            profile: profile
        )
        let response: Response = try await client.functions.invoke("gemini", options: SupabaseService.geminiOptions(body: request))
        var picks: [OutfitSlot: [UUID]] = [:]
        for pick in response.picks {
            guard let slot = OutfitSlot(rawValue: pick.slot) else { continue }
            let allowed = Set((candidates[slot] ?? []).map(\.id))
            picks[slot] = pick.item_ids.compactMap(UUID.init(uuidString:)).filter(allowed.contains)
        }
        return Result(picks: picks, note: response.note)
    }
}
