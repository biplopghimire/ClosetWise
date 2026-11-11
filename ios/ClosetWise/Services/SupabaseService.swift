import Foundation
import Supabase

/// Shared Supabase client. Reads the project URL and anon key from Info.plist
/// (filled from Config/Secrets.xcconfig). Returns nil until those are set, so the
/// app still runs on sample data during UI work.
enum SupabaseService {
    static let client: SupabaseClient? = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            let url = URL(string: urlString), url.host != nil, !key.isEmpty
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()

    static var isConfigured: Bool { client != nil }

    /// Options for calling the `gemini` Edge Function. Sends the user's Gemini key
    /// (Settings → Gemini API key) in `x-gemini-key` so calls use their own quota.
    static func geminiOptions(body: some Encodable) -> FunctionInvokeOptions {
        FunctionInvokeOptions(headers: GeminiKey.current.map { ["x-gemini-key": $0] } ?? [:], body: body)
    }
}
