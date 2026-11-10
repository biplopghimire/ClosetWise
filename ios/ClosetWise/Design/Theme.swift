import SwiftUI

/// Design tokens taken from the Figma wireframes.
enum Theme {
    static let primary = Color(hex: 0x22A06B)       // buttons, selected tabs, accent numbers
    static let mint = Color(hex: 0xE7F4EE)          // stat cards, item tile backgrounds
    static let mintStrong = Color(hex: 0xD5EDE2)
    static let ink = Color(hex: 0x16302A)           // headings
    static let secondaryText = Color(hex: 0x6B7A75)
    static let border = Color(hex: 0xDDE7E3)

    static let corner: CGFloat = 12
    static let pad: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
