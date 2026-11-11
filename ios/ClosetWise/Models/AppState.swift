import Foundation
import Observation

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var onboarded: Bool = false

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? "" }
    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "🧥" : String(letters).uppercased()
    }

    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// Cross-screen navigation: which tab is showing, and filters other screens ask for.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable { case home, closet, outfits, add, check }
    var tab: Tab = .home
    var closetFilter: ItemCategory?
    /// A piece to open the Outfits tab on, locked in place ("Style this piece").
    var outfitStart: WardrobeItem?
}
