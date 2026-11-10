import Foundation
import Supabase
import UIKit

/// Sends the on-device check (shortlists + style profile + photo) to Gemini via the
/// `gemini` Edge Function's `judge_purchase` action for a second opinion and a
/// plain-language explanation. Returns nil when Supabase isn't set up or the user
/// isn't signed in, so the local result stands on its own.
enum PurchaseCheckService {
    struct Judgment: Decodable, Equatable {
        let verdict: String
        let explanation: String
        let styleNotes: String

        enum CodingKeys: String, CodingKey { case verdict, explanation, styleNotes = "style_notes" }
    }

    private struct Piece: Encodable {
        let name, category, kind, color, fit, material, style: String
        let silhouette: String?
        let formality: Int
        let wears: Int
        let similarity: Double?

        init(_ i: WardrobeItem, similarity: Double? = nil) {
            name = i.name; category = i.category.rawValue; kind = i.kind.rawValue; color = i.color
            fit = i.fit.rawValue; material = i.material; style = i.style; silhouette = i.silhouette
            formality = i.formality; wears = i.wearCount; self.similarity = similarity.map { ($0 * 100).rounded() / 100 }
        }
    }

    private struct Request: Encodable {
        let action = "judge_purchase"
        let product: Piece
        let price: Double?
        let similar: [Piece]
        let compatible: [Piece]
        let outfit_count: Int
        let new_outfit_count: Int
        let style_fit: Int
        let style_reasons: [String]
        let local_verdict: String
        let profile: StyleContext
        let image_base64: String?
    }

    @MainActor static func makeTask(similar: Int, hasPhoto: Bool) -> GeminiTask {
        GeminiTask(title: "ClosetWise is trying it on", steps: [
            "Unlocking your closet",
            similar == 0
                ? "Taking the item\(hasPhoto ? " photo" : "") and your style to the fitting room"
                : "Taking the item\(hasPhoto ? " photo" : ""), \(similar) look-alike\(similar == 1 ? "" : "s") and your style to the fitting room",
            "Seeing how it hangs with the rest of your closet",
        ])
    }

    /// Returns nil (and marks `progress` failed or skipped) when Gemini can't answer;
    /// the on-device result stands on its own.
    @MainActor
    static func judge(_ r: PurchaseCheckResult, store: ClosetStore, progress: GeminiTask? = nil) async -> Judgment? {
        progress?.step(0)
        guard let client = SupabaseService.client else { progress?.fail("Supabase isn't configured — showing the on-device check."); return nil }
        guard await Cloud.shared.ensureSession() != nil else { progress?.fail("Couldn't sign in — showing the on-device check."); return nil }
        progress?.step(1)
        let image = r.product.photo.flatMap(ClosetStore.photo)?.resized(maxSide: 768).jpegData(compressionQuality: 0.7)?.base64EncodedString()
        let request = Request(
            product: Piece(r.product),
            price: r.product.price.map { NSDecimalNumber(decimal: $0).doubleValue },
            similar: r.duplicates.prefix(5).map { Piece($0.item, similarity: $0.score) },
            compatible: r.compatible.prefix(12).map { Piece($0) },
            outfit_count: r.outfits.count,
            new_outfit_count: r.newOutfitCount,
            style_fit: r.styleFit.score,
            style_reasons: r.styleFit.reasons.map { ($0.positive ? "+ " : "- ") + $0.text },
            local_verdict: r.verdict.rawValue,
            profile: store.styleContext,
            image_base64: image
        )
        progress?.step(2)
        do {
            let judgment: Judgment = try await client.functions.invoke("gemini", options: FunctionInvokeOptions(body: request))
            progress?.succeed("ClosetWise agrees with the evidence below" + (judgment.verdict == r.verdict.rawValue ? "." : " — see its verdict above."))
            return judgment
        } catch FunctionsError.httpError(let code, _) where code == 503 {
            progress?.fail("The fitting room's packed — showing the on-device check.")
        } catch {
            progress?.fail("ClosetWise couldn't get a second look — showing the on-device check.")
        }
        return nil
    }
}
