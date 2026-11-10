import Foundation

/// Perceptual colour comparison (CIE Lab, ΔE 1976) and colour-name normalisation.
enum ColorMath {
    struct Lab { let l, a, b: Double }

    static func lab(_ hex: UInt32) -> Lab {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255)
        let g = lin(Double((hex >> 8) & 0xFF) / 255)
        let b = lin(Double(hex & 0xFF) / 255)
        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = (r * 0.2126 + g * 0.7152 + b * 0.0722)
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return Lab(l: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)))
    }

    /// 0 = identical; ~2 just noticeable; >40 clearly different colours.
    static func deltaE(_ a: UInt32, _ b: UInt32) -> Double {
        let x = lab(a), y = lab(b)
        return sqrt(pow(x.l - y.l, 2) + pow(x.a - y.a, 2) + pow(x.b - y.b, 2))
    }

    /// How alike two colours look, 0…1.
    static func similarity(_ a: UInt32, _ b: UInt32) -> Double {
        let d = deltaE(a, b)
        switch d {
        case ..<10: return 1
        case ..<20: return 0.75
        case ..<32: return 0.45
        case ..<45: return 0.2
        default: return 0
        }
    }

    /// Maps retailer colour names onto the app's palette names.
    static let synonyms: [String: String] = [
        "jet": "black", "onyx": "black", "noir": "black", "ink": "black",
        "ivory": "cream", "ecru": "cream", "off-white": "cream", "oat": "cream", "oatmeal": "cream", "bone": "cream", "stone": "beige",
        "camel": "beige", "khaki": "beige", "sand": "beige", "tan": "beige", "taupe": "beige",
        "charcoal": "grey", "gray": "grey", "heather": "grey", "silver": "grey", "slate": "grey",
        "chocolate": "brown", "cognac": "brown", "mocha": "brown", "rust": "orange", "terracotta": "orange",
        "indigo": "denim", "light wash": "denim", "dark wash": "denim", "mid wash": "denim",
        "sky": "blue", "cobalt": "blue", "light blue": "blue", "royal": "blue", "midnight": "navy",
        "sage": "green", "forest": "green", "emerald": "green", "mint": "green", "khaki green": "olive", "army": "olive",
        "burgundy": "red", "wine": "red", "maroon": "red", "cherry": "red", "scarlet": "red",
        "blush": "pink", "rose": "pink", "fuchsia": "pink", "lilac": "purple", "lavender": "purple", "plum": "purple",
        "mustard": "yellow", "lemon": "yellow", "butter": "yellow", "coral": "orange",
    ]

    /// Palette name + hex for a free-text colour, if recognisable.
    static func normalize(_ text: String) -> (name: String, hex: UInt32)? {
        let t = text.lowercased()
        let palette = StylePreferences.palette
        for (word, name) in synonyms.sorted(by: { $0.key.count > $1.key.count }) where t.contains(word) {
            if let hex = palette.first(where: { $0.name == name })?.hex { return (name, hex) }
        }
        for entry in palette where t.range(of: "\\b\(entry.name)\\b", options: .regularExpression) != nil {
            return (entry.name, entry.hex)
        }
        return nil
    }
}
