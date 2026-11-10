import Foundation

/// Today's weather where the user is (from Open-Meteo), boiled down to what matters for getting dressed.
struct WeatherNow: Codable, Equatable {
    var tempC: Double
    /// "Feels like" right now.
    var feelsC: Double
    var highC: Double
    var lowC: Double
    /// Highest chance of rain or snow today, 0…100.
    var precipChance: Int
    /// WMO weather code (0 clear … 95+ thunderstorm).
    var code: Int
    var windKmh: Double
    var place: String?
    var fetchedAt: Date

    enum Band: String { case hot, warm, mild, cool, cold, freezing }

    /// The temperature to dress for: what it feels like now, leaning toward the day's high while it's daytime.
    var dressForC: Double {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour >= 6 && hour < 17 ? (feelsC + max(feelsC, highC)) / 2 : feelsC
    }

    var band: Band {
        switch dressForC {
        case 27...: .hot
        case 21..<27: .warm
        case 15..<21: .mild
        case 8..<15: .cool
        case 0..<8: .cold
        default: .freezing
        }
    }

    var isSnowy: Bool { (71...77).contains(code) || (85...86).contains(code) }
    var isRainy: Bool {
        !isSnowy && ((51...67).contains(code) || (80...82).contains(code) || code >= 95 || precipChance >= 50)
    }
    var isWindy: Bool { windKmh >= 30 }

    var condition: String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95...: "Thunderstorms"
        default: "Mixed"
        }
    }

    var symbol: String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3, 45, 48: "cloud"
        case 51...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...: "cloud.bolt.rain"
        default: "cloud.sun"
        }
    }

    /// "14° · Rain · Pittsburgh"
    var headline: String {
        [Self.degrees(feelsC), condition, place].compactMap { $0 }.joined(separator: " · ")
    }

    /// What the weather means for today's outfit, in a few words.
    var advice: String {
        var parts: [String]
        switch band {
        case .hot: parts = ["Hot one — keep it light"]
        case .warm: parts = ["Warm — no layer needed"]
        case .mild: parts = ["Mild — a light layer is handy"]
        case .cool: parts = ["Cool — bring a jacket"]
        case .cold: parts = ["Cold — wear something warm"]
        case .freezing: parts = ["Freezing — bundle up"]
        }
        if isSnowy { parts.append("snow on the way") } else if isRainy { parts.append("rain likely") }
        return parts.joined(separator: ", ")
    }

    /// Formats in the phone's units (°F in the US, °C elsewhere).
    static func degrees(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// How warm clothes are, and how warm an outfit should be for the weather.
enum Warmth {
    /// Rough insulation of one piece (a tee ≈ 1, a winter coat ≈ 5).
    static func of(_ item: WardrobeItem) -> Double {
        let name = item.name.lowercased(), material = item.material.lowercased()
        var w: Double
        switch item.kind {
        case .tee: w = name.contains("tank") || name.contains("cami") ? 0.4 : 1
        case .shirt: w = 1.5
        case .knit: w = name.contains("cardigan") ? 2.5 : 3
        case .hoodie: w = 2.5
        case .jacket: w = name.contains("puffer") || name.contains("parka") ? 4.5 : 3
        case .coat: w = 5
        case .trousers: w = 2
        case .skirt: w = name.contains("mini") ? 0.6 : 1.2
        case .shorts: w = 0.2
        case .shoes: w = isOpenShoe(item) ? 0 : name.contains("boot") ? 1 : 0.5
        }
        if ["wool", "cashmere", "fleece", "down", "shearling", "sherpa", "corduroy", "flannel"].contains(where: material.contains) { w += 1 }
        if ["linen", "mesh", "seersucker", "chiffon"].contains(where: material.contains) { w -= 0.5 }
        if material.contains("denim") && item.category != .bottom { w += 0.3 }
        return max(0, w)
    }

    static func isOpenShoe(_ item: WardrobeItem) -> Bool {
        let name = item.name.lowercased()
        return ["sandal", "slide", "flip", "mule", "espadrille"].contains(where: name.contains)
    }

    /// The outfit warmth that feels right at a given temperature.
    static func target(forC t: Double) -> Double {
        switch t {
        case 27...: 2.5
        case 21..<27: 3.8
        case 15..<21: 5.2
        case 8..<15: 7.5
        case 0..<8: 9.5
        default: 11
        }
    }

    /// How well an outfit suits the weather. `blocked` rules out outfits nobody should wear in it.
    /// Hot path: called for every combination, so it builds no strings.
    static func fit(_ pieces: [WardrobeItem], _ weather: WeatherNow) -> (score: Double, blocked: Bool) {
        let t = weather.dressForC
        var total = 0.0
        var layer = false, warmTop = false, shorts = false, openShoes = false, heavy = false, suede = false
        for p in pieces {
            let w = of(p)
            total += w
            if p.category == .outerwear { layer = true }
            if p.kind == .knit || p.kind == .hoodie { warmTop = true }
            if p.kind == .shorts { shorts = true }
            if p.kind == .shoes && isOpenShoe(p) { openShoes = true }
            if p.kind == .coat || w >= 4.5 { heavy = true }
            if p.material.localizedCaseInsensitiveContains("suede") { suede = true }
        }
        if shorts && t < 16 { return (0, true) }
        if openShoes && (t < 10 || weather.isSnowy) { return (0, true) }
        if heavy && t > 22 { return (0, true) }
        if t < 4 && !layer && !warmTop { return (0, true) }

        var score = -max(0, abs(total - target(forC: t)) - 1) * 0.7
        if t < 15 && !layer && !warmTop { score -= 1.5 }
        if shorts && t < 20 { score -= 1.5 }   // legal, but not the first thing to suggest
        if weather.isRainy || weather.isSnowy {
            if openShoes { score -= 2 }
            if suede { score -= 1 }
            if layer { score += 0.5 }
        }
        return (score, false)
    }

    /// Whether a single piece can be worn today at all (used to pick which pieces to combine).
    static func wearable(_ item: WardrobeItem, _ weather: WeatherNow) -> Bool {
        let t = weather.dressForC
        if item.kind == .shorts && t < 16 { return false }
        if isOpenShoe(item) && (t < 10 || weather.isSnowy) { return false }
        if (item.kind == .coat || of(item) >= 4.5) && t > 22 { return false }
        return true
    }

    /// A short line on why the outfit suits today's weather, if it does something about it.
    static func note(_ pieces: [WardrobeItem], _ weather: WeatherNow) -> String? {
        let layer = pieces.first { $0.category == .outerwear }
        let degrees = WeatherNow.degrees(weather.dressForC)
        switch weather.band {
        case .cold, .freezing, .cool:
            if let layer { return "\(degrees) out — your \(layer.name.lowercased()) keeps you warm" }
            if let knit = pieces.first(where: { $0.kind == .knit || $0.kind == .hoodie }) {
                return "Cool out — the \(knit.name.lowercased()) does the work"
            }
        case .hot, .warm:
            if pieces.contains(where: { $0.kind == .shorts || $0.kind == .tee }) {
                return "\(degrees) today — light and easy to wear"
            }
        case .mild:
            if let layer { return "Mild with a chance to cool — \(layer.name.lowercased()) on top" }
        }
        if weather.isRainy || weather.isSnowy, let layer {
            return "\(weather.isSnowy ? "Snow" : "Rain") likely — the \(layer.name.lowercased()) has you covered"
        }
        return nil
    }
}
