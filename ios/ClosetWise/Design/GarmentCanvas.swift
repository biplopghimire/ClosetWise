import SwiftUI
import UIKit

enum HangerStyle { case wood, matte, none }
enum GarmentFace { case front, back, side }

/// Draws one garment (front, back or side-on) with optional hanger, in the
/// artwork's own coordinate space scaled to fit (top-aligned, centred).
struct GarmentCanvas: View {
    let kind: GarmentKind
    var face: GarmentFace = .front
    let color: Color
    var trim: Color?
    var hanger: HangerStyle = .none
    /// Extra space above the artwork (in artwork units) so the hanger hook isn't clipped.
    var headroom: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let box = kind.canvas
            let s = min(size.width / box.width, size.height / (box.height + headroom))
            let y = kind == .shoes ? (size.height - box.height * s) / 2 : headroom * s
            ctx.translateBy(x: (size.width - box.width * s) / 2, y: y)
            ctx.scaleBy(x: s, y: s)
            let painter = GarmentPainter(kind: kind, color: color, trim: trim ?? color.mixed(-0.12), blur: 2.4 * s)
            switch face {
            case .side: painter.paintSide(&ctx, hanger: hanger)
            case .front: painter.paint(&ctx, back: false, hanger: hanger)
            case .back: painter.paint(&ctx, back: true, hanger: hanger)
            }
        }
    }
}

private struct GarmentPainter {
    let kind: GarmentKind
    let color: Color
    let trim: Color
    let blur: CGFloat

    private func p(_ d: String) -> Path { SVGPath.path(d) }
    private func union(_ ds: [String]) -> Path {
        var path = Path()
        for d in ds { path.addPath(p(d)) }
        return path
    }

    private var canvasRect: CGRect { CGRect(origin: .zero, size: kind.canvas) }

    // MARK: Front / back

    func paint(_ ctx: inout GraphicsContext, back: Bool, hanger: HangerStyle) {
        let art = GarmentArtLibrary.art(kind, back: back)

        if let hood = art.hood {
            ctx.fill(p(hood), with: .color(color))
            ctx.fill(p(hood), with: .color(.black.opacity(0.22)))
        }
        if let under = art.under { ctx.fill(p(under), with: .color(color.mixed(-0.42))) }
        if kind.hangs && hanger != .none { paintHanger(&ctx, style: hanger) }

        ctx.fill(p(art.body), with: .color(color))
        for d in art.sleeves { ctx.fill(p(d), with: .color(color)) }

        let silhouette = union(art.silhouette)
        ctx.drawLayer { layer in
            layer.clip(to: silhouette)
            for panel in art.panels { layer.fill(p(panel.d), with: .color(color.mixed(panel.t))) }
            for d in art.ribs {
                layer.fill(p(d), with: .color(trim))
                paintRibTexture(&layer, in: p(d))
            }
            if kind == .knit { paintKnitTexture(&layer) }

            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                for d in art.folds {
                    soft.stroke(p(d), with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    soft.stroke(p(d).offsetBy(dx: 2.2, dy: 0), with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                for d in art.sleeves { soft.stroke(p(d), with: .color(.black.opacity(0.2)), lineWidth: 3) }
            }

            layer.fill(Path(canvasRect), with: .linearGradient(volume, startPoint: .zero, endPoint: CGPoint(x: canvasRect.width, y: 0)))
            layer.fill(Path(canvasRect), with: .linearGradient(drape, startPoint: .zero, endPoint: CGPoint(x: 0, y: canvasRect.height)))
        }

        for d in art.seams { ctx.stroke(p(d), with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)) }
        for d in art.stitches {
            ctx.stroke(p(d), with: .color(color.mixed(0.35).opacity(0.5)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [1.6, 1.4]))
        }
        for d in art.cords {
            ctx.stroke(p(d), with: .color(trim), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            if let end = p(d).currentPoint {
                ctx.fill(Path(roundedRect: CGRect(x: end.x - 1.4, y: end.y - 1, width: 2.8, height: 6), cornerRadius: 1), with: .color(trim.mixed(-0.3)))
            }
        }
        for b in art.buttons {
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 2.6, y: b.y - 2.6, width: 5.2, height: 5.2)), with: .color(trim.mixed(-0.15)))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 1.5, y: b.y - 1.6, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.45)))
        }
    }

    // MARK: Side-on (resting on the rail)

    func paintSide(_ ctx: inout GraphicsContext, hanger: HangerStyle) {
        let side = GarmentArtLibrary.side(kind)
        let cuff = side.cuff, hem = side.hem
        if hanger != .none {
            ctx.fill(p(GarmentArtLibrary.sideHangerNeck), with: hanger == .wood ? .linearGradient(wood, startPoint: CGPoint(x: 0, y: 35), endPoint: CGPoint(x: 0, y: 50)) : .color(Theme.ink.opacity(0.85)))
            paintHook(&ctx)
        }
        if let hood = side.hood {
            ctx.fill(p(hood), with: .color(color.mixed(-0.14)))
            ctx.stroke(p(hood), with: .color(.black.opacity(0.2)), lineWidth: 1.2)
        }

        let body = p(side.body)
        ctx.fill(body, with: .color(color))
        ctx.drawLayer { layer in
            layer.clip(to: body)
            if kind == .knit { paintKnitTexture(&layer) }
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                let lines: [(String, Color, CGFloat)] = [
                    ("M90,\(cuff + 10) C87,150 92,190 88,\(hem - 4)", .black.opacity(0.24), 2.6),
                    ("M106,\(cuff + 6) C109,140 104,186 108,\(hem - 2)", .black.opacity(0.17), 2.2),
                    ("M99,\(cuff + 30) C97,170 101,205 98,\(hem - 2)", .black.opacity(0.1), 2),
                    ("M84,\(cuff + 50) C86,160 85,200 86,\(hem - 6)", .white.opacity(0.2), 1.4),
                    ("M80,\(cuff + 6) C90,\(cuff + 12) 110,\(cuff + 12) 120,\(cuff + 7)", .black.opacity(0.4), 6),
                    ("M84,\(hem + 1) C92,\(hem + 6) 108,\(hem + 6) 116,\(hem + 1)", .black.opacity(0.32), 6),
                ]
                for (d, c, w) in lines { soft.stroke(p(d), with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round)) }
            }
            layer.fill(Path(canvasRect), with: .linearGradient(sideVolume, startPoint: CGPoint(x: 80, y: 0), endPoint: CGPoint(x: 120, y: 0)))
            layer.fill(Path(canvasRect), with: .linearGradient(drape, startPoint: .zero, endPoint: CGPoint(x: 0, y: canvasRect.height)))
        }

        let sleeve = p(side.sleeve)
        ctx.fill(sleeve, with: .color(color))
        ctx.drawLayer { layer in
            layer.clip(to: sleeve)
            layer.drawLayer { soft in
                soft.addFilter(.blur(radius: blur))
                let lines: [(String, Color, CGFloat)] = [
                    ("M91,62 C88,78 90,\(cuff - 14) 91,\(cuff)", .black.opacity(0.16), 2.6),
                    ("M109,58 C112,76 110,\(cuff - 14) 109,\(cuff)", .black.opacity(0.2), 2.6),
                    ("M84,53 C92,49 108,49 116,53", .black.opacity(0.24), 3.6),
                    ("M81,\(cuff - 2) C92,\(cuff + 4) 108,\(cuff + 5) 119,\(cuff + 2)", .black.opacity(0.34), 3.2),
                    ("M85,60 C84,80 85,\(cuff - 20) 85,\(cuff - 4)", .white.opacity(0.22), 1.4),
                ]
                for (d, c, w) in lines { soft.stroke(p(d), with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round)) }
            }
            layer.fill(Path(canvasRect), with: .linearGradient(sideVolume, startPoint: CGPoint(x: 80, y: 0), endPoint: CGPoint(x: 120, y: 0)))
        }

        let dash = StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [1.6, 1.4])
        ctx.stroke(p("M82,\(cuff + 1) C92,\(cuff + 6) 108,\(cuff + 7) 118,\(cuff + 4)"), with: .color(color.mixed(0.35).opacity(0.45)), style: dash)
        ctx.stroke(p("M86,\(hem - 3) C92,\(hem + 1) 109,\(hem + 1) 115,\(hem - 3)"), with: .color(color.mixed(0.35).opacity(0.4)), style: dash)
        let collar = Path(ellipseIn: CGRect(x: 90, y: 42.8, width: 20, height: 6.4))
        ctx.fill(collar, with: .color(trim))
        ctx.stroke(collar, with: .color(.black.opacity(0.2)), lineWidth: 0.6)
    }

    // MARK: Hanger

    private func paintHanger(_ ctx: inout GraphicsContext, style: HangerStyle) {
        let bar = p(GarmentArtLibrary.bar)
        ctx.stroke(bar.offsetBy(dx: 0.6, dy: 1.6), with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 9.5, lineCap: .round))
        let shading: GraphicsContext.Shading = style == .wood
            ? .linearGradient(wood, startPoint: CGPoint(x: 0, y: 32), endPoint: CGPoint(x: 0, y: 62))
            : .color(Theme.ink.opacity(0.85))
        ctx.stroke(bar, with: shading, style: StrokeStyle(lineWidth: 8.5, lineCap: .round))
        ctx.stroke(p(GarmentArtLibrary.barHighlight), with: .color(.white.opacity(style == .wood ? 0.3 : 0.14)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        paintHook(&ctx)
    }

    private func paintHook(_ ctx: inout GraphicsContext) {
        let hook = p(GarmentArtLibrary.hook)
        ctx.stroke(hook.offsetBy(dx: 0.9, dy: 1.1), with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        ctx.stroke(hook, with: .linearGradient(chrome, startPoint: CGPoint(x: 98.5, y: 0), endPoint: CGPoint(x: 101.7, y: 0)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        ctx.stroke(p(GarmentArtLibrary.hookHighlight), with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
        ctx.fill(Path(roundedRect: CGRect(x: 96, y: 27, width: 8, height: 9), cornerRadius: 2), with: .linearGradient(chrome, startPoint: CGPoint(x: 96, y: 0), endPoint: CGPoint(x: 104, y: 0)))
    }

    // MARK: Textures

    private func paintRibTexture(_ ctx: inout GraphicsContext, in shape: Path) {
        let r = shape.boundingRect
        ctx.drawLayer { l in
            l.clip(to: shape)
            var x = r.minX
            while x < r.maxX {
                l.fill(Path(CGRect(x: x, y: r.minY, width: 1.1, height: r.height)), with: .color(.black.opacity(0.2)))
                x += 2.6
            }
        }
    }

    private func paintKnitTexture(_ ctx: inout GraphicsContext) {
        var chevrons = Path()
        var y: CGFloat = 0
        while y < canvasRect.height {
            var x: CGFloat = 0
            while x < canvasRect.width {
                chevrons.move(to: CGPoint(x: x, y: y))
                chevrons.addLine(to: CGPoint(x: x + 2.5, y: y + 4))
                chevrons.addLine(to: CGPoint(x: x + 5, y: y))
                x += 5
            }
            y += 4
        }
        ctx.stroke(chevrons, with: .color(.black.opacity(0.09)), lineWidth: 0.7)
    }

    // MARK: Gradients

    private var volume: Gradient {
        Gradient(stops: [
            .init(color: .black.opacity(0.34), location: 0), .init(color: .black.opacity(0.1), location: 0.16),
            .init(color: .white.opacity(0.07), location: 0.42), .init(color: .white.opacity(0.04), location: 0.58),
            .init(color: .black.opacity(0.12), location: 0.84), .init(color: .black.opacity(0.38), location: 1),
        ])
    }
    private var drape: Gradient {
        Gradient(stops: [
            .init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.22),
            .init(color: .black.opacity(0.04), location: 0.75), .init(color: .black.opacity(0.2), location: 1),
        ])
    }
    private var sideVolume: Gradient {
        Gradient(stops: [
            .init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0.04), location: 0.28),
            .init(color: .black.opacity(0.08), location: 0.7), .init(color: .black.opacity(0.3), location: 0.95),
            .init(color: .black.opacity(0.18), location: 1),
        ])
    }
    private var wood: Gradient {
        let sienna = Color(hex: 0xA0522D)
        return Gradient(stops: [
            .init(color: sienna.mixed(0.45), location: 0), .init(color: sienna.mixed(-0.2), location: 0.45),
            .init(color: sienna.mixed(-0.55), location: 1),
        ])
    }
    private var chrome: Gradient {
        Gradient(stops: [
            .init(color: Color(white: 0.75), location: 0), .init(color: .white, location: 0.35),
            .init(color: Color(white: 0.32), location: 0.78), .init(color: Color(white: 0.7), location: 1),
        ])
    }
}

extension Color {
    /// Mixes toward white (positive) or black (negative), like CSS color-mix.
    func mixed(_ amount: Double) -> Color {
        guard amount != 0 else { return self }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let t = CGFloat(min(1, abs(amount)))
        let target: CGFloat = amount > 0 ? 1 : 0
        return Color(red: r + (target - r) * t, green: g + (target - g) * t, blue: b + (target - b) * t, opacity: a)
    }
}
