import Foundation
import Observation
import Security

/// The user's own Gemini API key, kept in the Keychain on this phone (never synced).
/// Sent with every call to the `gemini` Edge Function so AI reads use the user's own quota.
/// A GEMINI_API_KEY in Secrets.xcconfig, if present, is used as a fallback for development.
@MainActor
@Observable
final class GeminiKey {
    static let shared = GeminiKey()

    private(set) var value: String?

    private init() { value = Self.read() ?? Self.buildKey }

    var isSet: Bool { value != nil }
    /// True when the key was entered in the app (and so can be removed there).
    var isFromApp: Bool { Self.read() != nil }
    /// "…abcd", enough to recognise the key without showing it.
    var hint: String? { value.map { "…" + $0.suffix(4) } }

    enum CheckError: LocalizedError {
        case invalid, unreachable(String)
        var errorDescription: String? {
            switch self {
            case .invalid: "Google says that key isn't valid. Copy it again from AI Studio."
            case .unreachable(let why): "Couldn't check the key right now (\(why)). Try again."
            }
        }
    }

    /// Checks the key with Google (listing models is free), then saves it to the Keychain.
    func save(_ raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15
        let status: Int
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw CheckError.unreachable(error.localizedDescription)
        }
        guard status == 200 else {
            if [400, 401, 403].contains(status) { throw CheckError.invalid }
            throw CheckError.unreachable("HTTP \(status)")
        }
        Self.write(key)
        value = key
    }

    func remove() {
        Self.delete()
        value = Self.buildKey
    }

    /// Key for requests; read from any thread (the Keychain is thread-safe).
    nonisolated static var current: String? { read() ?? buildKey }

    // MARK: Storage

    nonisolated private static let account = "gemini-api-key"
    nonisolated private static var service: String { Bundle.main.bundleIdentifier ?? "ClosetWise" }

    nonisolated private static var buildKey: String? {
        guard let key = (Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces), !key.isEmpty else { return nil }
        return key
    }

    nonisolated private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    nonisolated private static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    nonisolated private static func write(_ key: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    nonisolated private static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
