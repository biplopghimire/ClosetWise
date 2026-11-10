import Foundation
import Supabase
import UIKit

/// Finds which closet pieces are in an outfit photo (ClosetWise / Gemini `detect_outfit`).
@MainActor
enum OutfitService {
    struct Detection {
        var itemIDs: [UUID]
        var notInCloset: [String]
    }

    enum DetectError: LocalizedError {
        case unavailable, busy, failed
        var errorDescription: String? {
            switch self {
            case .unavailable: "Couldn't reach ClosetWise — pick the pieces yourself below."
            case .busy: "The fitting room's packed — pick the pieces yourself, or try again in a minute."
            case .failed: "ClosetWise couldn't read that photo — pick the pieces yourself below."
            }
        }
    }

    static func task() -> GeminiTask {
        GeminiTask(title: "ClosetWise is checking the mirror", steps: [
            "Unlocking your closet",
            "Spotting each piece you're wearing",
            "Matching them to your rails and shelves",
        ])
    }

    private struct Piece: Encodable { let id, name, category, color, fit: String; let silhouette: String? }
    private struct Request: Encodable { let action = "detect_outfit"; let image_base64: String; let mime_type = "image/jpeg"; let closet: [Piece] }
    private struct Match: Decodable { let item_id: String; let confidence: Double }
    private struct Response: Decodable { let matches: [Match]; let not_in_closet: [String] }

    static func detect(_ image: UIImage, store: ClosetStore, task: GeminiTask) async throws -> Detection {
        task.step(0)
        guard let client = SupabaseService.client, await Cloud.shared.ensureSession() != nil,
              let jpeg = image.resized(maxSide: 1024).jpegData(compressionQuality: 0.8) else { throw DetectError.unavailable }
        task.step(1)
        let closet = store.items.map {
            Piece(id: $0.id.uuidString, name: $0.name, category: $0.category.rawValue, color: $0.color, fit: $0.fit.rawValue, silhouette: $0.silhouette)
        }
        let response: Response
        do {
            response = try await client.functions.invoke("gemini", options: FunctionInvokeOptions(
                body: Request(image_base64: jpeg.base64EncodedString(), closet: closet)))
        } catch FunctionsError.httpError(let code, _) where code == 503 {
            throw DetectError.busy
        } catch {
            throw DetectError.failed
        }
        task.step(2)
        let ids = response.matches.filter { $0.confidence >= 0.5 }.compactMap { UUID(uuidString: $0.item_id) }
        var seen = Set<UUID>()
        return Detection(itemIDs: ids.filter { seen.insert($0).inserted }, notInCloset: response.not_in_closet)
    }
}
