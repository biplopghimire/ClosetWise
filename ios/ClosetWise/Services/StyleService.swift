import Foundation
import Supabase

/// Asks Gemini (via the `gemini` Edge Function) to read the user's style from what
/// they've told us, what they wear, and their inspiration photos. The function also
/// saves the result to `style_profiles`, so purchase checks and outfit judgments use it.
enum StyleService {
    enum StyleError: LocalizedError {
        case notConfigured, notSignedIn, busy
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Connect Supabase (Config/Secrets.xcconfig) so ClosetWise can write this."
            case .notSignedIn: "Couldn't sign in to Supabase — check that anonymous sign-ins are on and you're online."
            case .busy: "The fitting room's packed right now — try again in a minute. Your learned style above is still up to date."
            }
        }
    }

    private struct Request: Encodable {
        let action = "style_summary"
        let profile: StyleContext
        let inspiration_images: [String]
    }

    private struct Response: Decodable {
        let summary: String
        let tags: [String]
        let fit_notes: String
    }

    /// Steps shown while this runs (indices match `refreshSummary`'s `progress.step` calls).
    @MainActor static func makeTask(photoCount: Int) -> GeminiTask {
        GeminiTask(title: "ClosetWise is going through your closet", steps: [
            "Unlocking your closet",
            photoCount > 0 ? "Folding up your style profile + \(photoCount) inspiration photo\(photoCount == 1 ? "" : "s")" : "Folding up your style profile and outfit history",
            "Sizing up your style",
            "Hanging up your new summary",
        ])
    }

    @MainActor
    static func refreshSummary(_ store: ClosetStore, progress: GeminiTask? = nil) async throws {
        progress?.step(0)
        guard let client = SupabaseService.client else { throw StyleError.notConfigured }
        guard await Cloud.shared.ensureSession() != nil else { throw StyleError.notSignedIn }

        progress?.step(1)
        let images = store.preferences.inspirationFiles.prefix(6).compactMap { name in
            store.inspirationImage(name)?.resized(maxSide: 768).jpegData(compressionQuality: 0.7)?.base64EncodedString()
        }
        progress?.step(2)
        let response: Response
        do {
            response = try await client.functions.invoke(
                "gemini",
                options: FunctionInvokeOptions(body: Request(profile: store.styleContext, inspiration_images: images))
            )
        } catch FunctionsError.httpError(let code, _) where code == 503 {
            throw StyleError.busy
        }
        progress?.step(3)
        store.geminiSummary = GeminiStyleSummary(summary: response.summary, tags: response.tags,
                                                 fitNotes: response.fit_notes, updatedAt: .now)
        store.save()
    }
}
