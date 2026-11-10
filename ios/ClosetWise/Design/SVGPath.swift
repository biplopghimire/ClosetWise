import SwiftUI

/// Minimal SVG path-data parser (absolute M, L, C, Q, Z), enough for the garment artwork.
/// Parsed paths are cached because the rail redraws them on every animation frame.
enum SVGPath {
    private static var cache: [String: Path] = [:]
    private static let lock = NSLock()

    static func path(_ d: String) -> Path {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[d] { return hit }
        let parsed = parse(d)
        cache[d] = parsed
        return parsed
    }

    private enum Token { case cmd(Character), num(CGFloat) }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter && c != "e" {
                tokens.append(.cmd(c)); i += 1
            } else if c.isNumber || c == "-" || c == "." {
                var j = i + 1
                var seenDot = c == "."
                while j < chars.count {
                    let n = chars[j]
                    if n.isNumber { j += 1 }
                    else if n == "." && !seenDot { seenDot = true; j += 1 }
                    else { break }
                }
                tokens.append(.num(CGFloat(Double(String(chars[i..<j])) ?? 0)))
                i = j
            } else {
                i += 1
            }
        }
        return tokens
    }

    private static func parse(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var i = 0
        var cmd: Character = "M"

        func number() -> CGFloat {
            guard i < tokens.count, case .num(let v) = tokens[i] else { return 0 }
            i += 1
            return v
        }
        func point() -> CGPoint { CGPoint(x: number(), y: number()) }

        while i < tokens.count {
            if case .cmd(let c) = tokens[i] { cmd = c; i += 1 }
            switch cmd {
            case "M": path.move(to: point()); cmd = "L"
            case "L": path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point(), p = point()
                path.addCurve(to: p, control1: c1, control2: c2)
            case "Q":
                let c = point(), p = point()
                path.addQuadCurve(to: p, control: c)
            case "Z", "z": path.closeSubpath(); cmd = "?"
            default: i += 1
            }
        }
        return path
    }
}
