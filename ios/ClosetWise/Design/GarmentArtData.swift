import CoreGraphics

/// Garment illustrations drawn in a 200 × 310 canvas (shoes: 200 × 110).
/// Hanging pieces (tee … coat) are adapted from the clothing-rail component's artwork.
enum GarmentKind: String, Codable, CaseIterable {
    case tee, knit, hoodie, shirt, jacket, coat
    case trousers, skirt, shorts, shoes

    /// Hangs on the rail (vs. folded on the shelf).
    var hangs: Bool {
        switch self {
        case .tee, .knit, .hoodie, .shirt, .jacket, .coat: true
        default: false
        }
    }

    var canvas: CGSize { self == .shoes ? CGSize(width: 200, height: 110) : CGSize(width: 200, height: 310) }

    /// Width of the piece when seen side-on, as a share of its front width.
    var sideWidth: CGFloat {
        switch self {
        case .hoodie: 0.33
        case .knit, .shirt: 0.25
        case .jacket, .coat: 0.27
        default: 0.23
        }
    }

    /// Lowest point of the drawn piece, used to size the rail.
    var hem: CGFloat {
        switch self {
        case .tee: 240
        case .knit: 232
        case .hoodie: 234
        case .shirt: 244
        case .jacket: 234
        case .coat: 296
        default: 300
        }
    }

    var hasHood: Bool { self == .hoodie }
    var longSleeve: Bool { self != .tee }
}

struct GarmentArt {
    var body: String
    var sleeves: [String] = []
    var under: String?
    var hood: String?
    var ribs: [String] = []
    var panels: [(d: String, t: Double)] = []
    var seams: [String] = []
    var stitches: [String] = []
    var folds: [String] = []
    var cords: [String] = []
    var buttons: [CGPoint] = []

    var silhouette: [String] { [body] + sleeves + (hood.map { [$0] } ?? []) }
}

enum GarmentArtLibrary {
    static func art(_ kind: GarmentKind, back: Bool) -> GarmentArt {
        switch kind {
        case .tee: back ? teeBack : teeFront
        case .knit: back ? knitBack : knitFront
        case .hoodie: back ? hoodieBack : hoodieFront
        case .shirt: back ? shirtBack : shirtFront
        case .jacket: back ? jacketBack : jacketFront
        case .coat: back ? coatBack : coatFront
        case .trousers: trousers
        case .skirt: skirt
        case .shorts: shorts
        case .shoes: shoes
        }
    }

    // MARK: Hanger

    static let hook = "M100,36 L100,-0.4 C100,-3.4 102.2,-4.2 103.9,-2.8 C104.9,-2 105.4,-1.2 105.6,-0.2"
    static let hookHighlight = "M99.5,30 L99.5,-0.2 C99.5,-2.4 101,-3.2 102.4,-2.6"
    static let bar = "M38,57 Q70,38 100,36 Q130,38 162,57"
    static let barHighlight = "M40,54.5 Q71,35.5 100,33.5 Q129,35.5 160,54.5"
    static let sideHangerNeck = "M97.8,35 L102.2,35 L104.5,50 L95.5,50 Z"

    // MARK: Side view (piece turned away on the rail)

    struct Side { let body: String; let sleeve: String; let hood: String?; let cuff: CGFloat; let hem: CGFloat }

    static func side(_ kind: GarmentKind) -> Side {
        let hem = kind.hem
        let cuff: CGFloat = kind.longSleeve ? hem - 24 : 104
        func n(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        let body = "M86,60 C85,96 88,132 85,168 C83,196 84,\(n(hem - 18)) 85,\(n(hem)) C92,\(n(hem + 5)) 109,\(n(hem + 5)) 116,\(n(hem)) C117,\(n(hem - 18)) 118,196 116,168 C113,132 116,96 114,60 Z"
        let sleeve = "M84,56 C84,47 90,43 100,43 C110,43 116,47 116,56 C117,\(n(cuff * 0.62)) 119,\(n(cuff - 14)) 119,\(n(cuff - 2)) C119,\(n(cuff + 4)) 116,\(n(cuff + 7)) 111,\(n(cuff + 7)) C100,\(n(cuff + 8)) 90,\(n(cuff + 6)) 83,\(n(cuff + 2)) C80,\(n(cuff - 1)) 80,\(n(cuff - 6)) 81,\(n(cuff - 10)) C83,\(n(cuff - 24)) 83,70 84,56 Z"
        let hood = kind.hasHood ? "M110,46 C128,36 138,54 134,76 C130,90 118,94 113,86 C113,74 112,60 110,46 Z" : nil
        return Side(body: body, sleeve: sleeve, hood: hood, cuff: cuff, hem: hem)
    }

    // MARK: Tee

    private static let teeSleeves = [
        "M44,45 C38,47 33,50 31,55 C24,64 17,76 13,92 C18,100 24,106 30,110 C35,106 42,102 48,102 C47,84 45,62 44,45 Z",
        "M156,45 C162,47 167,50 169,55 C176,64 183,76 187,92 C182,100 176,106 170,110 C165,106 158,102 152,102 C153,84 155,62 156,45 Z",
    ]
    private static let teeStitches = ["M14,93 C19,101 25,106 30,109", "M186,93 C181,101 175,106 170,109", "M50,229 C74,233 126,233 150,229"]

    static let teeFront = GarmentArt(
        body: "M80,34 C88,45 112,45 120,34 C132,36 146,40 156,45 C160,48 163,52 164,57 C158,72 152,88 152,102 L153,236 C128,241 72,241 47,236 L48,102 C48,88 42,72 36,57 C37,52 40,48 44,45 C54,40 68,36 80,34 Z",
        sleeves: teeSleeves,
        under: "M80,34 C90,30 110,30 120,34 C112,45 88,45 80,34 Z",
        ribs: ["M80,34 C88,45 112,45 120,34 L124,36 C114,50 86,50 76,36 Z"],
        seams: ["M80,34 C68,36 54,40 44,45", "M120,34 C132,36 146,40 156,45", "M48,102 C47,84 45,62 44,45", "M152,102 C153,84 155,62 156,45"],
        stitches: teeStitches,
        folds: ["M40,56 C58,76 76,94 90,120", "M160,56 C142,76 124,94 110,120", "M70,126 C66,164 72,204 66,234", "M131,128 C135,164 129,204 134,234", "M100,112 C98,160 103,204 100,236", "M31,62 C27,74 23,84 21,96", "M169,62 C173,74 177,84 179,96", "M78,50 C88,58 112,58 122,50"]
    )

    static let teeBack = GarmentArt(
        body: "M80,34 C90,31 110,31 120,34 C132,36 146,40 156,45 C160,48 163,52 164,57 C158,72 152,88 152,102 L153,236 C128,241 72,241 47,236 L48,102 C48,88 42,72 36,57 C37,52 40,48 44,45 C54,40 68,36 80,34 Z",
        sleeves: teeSleeves,
        ribs: ["M80,34 C90,31 110,31 120,34 L121,38 C110,35 90,35 79,38 Z"],
        seams: ["M80,34 C68,36 54,40 44,45", "M120,34 C132,36 146,40 156,45"],
        stitches: teeStitches,
        folds: ["M40,56 C60,74 80,88 96,104", "M160,56 C140,74 120,88 104,104", "M72,120 C68,164 74,204 68,234", "M128,122 C132,164 126,204 132,234", "M100,60 C98,150 102,200 100,236", "M31,62 C27,74 23,84 21,96", "M169,62 C173,74 177,84 179,96"]
    )

    // MARK: Knit

    private static let knitSleeves = [
        "M42,46 C32,52 27,62 26,76 L20,216 C26,221 36,222 44,219 L47,98 C46,80 45,62 42,46 Z",
        "M158,46 C168,52 173,62 174,76 L180,216 C174,221 164,222 156,219 L153,98 C154,80 155,62 158,46 Z",
    ]
    private static let knitCuffs = [
        "M37,211 L163,211 L163,226 C140,231 60,231 37,226 Z",
        "M21,203 L45,206 L44,219 C36,222 26,221 20,216 Z",
        "M179,203 L155,206 L156,219 C164,222 174,221 180,216 Z",
    ]
    private static let knitSeams = ["M47,98 C46,80 45,62 42,46", "M153,98 C154,80 155,62 158,46"]

    static let knitFront = GarmentArt(
        body: "M80,34 C88,46 112,46 120,34 L158,46 C162,52 163,60 163,70 L163,226 C140,231 60,231 37,226 L37,70 C37,60 38,52 42,46 Z",
        sleeves: knitSleeves,
        under: "M80,34 C90,30 110,30 120,34 C112,46 88,46 80,34 Z",
        ribs: knitCuffs + ["M80,34 C88,46 112,46 120,34 L125,37 C115,53 85,53 75,37 Z"],
        seams: knitSeams,
        folds: ["M66,60 C62,110 70,160 64,210", "M134,62 C138,112 130,162 136,210", "M100,56 C98,110 102,160 100,210", "M33,80 C31,130 33,170 30,204", "M167,80 C169,130 167,170 170,204"]
    )

    static let knitBack = GarmentArt(
        body: "M80,34 C90,31 110,31 120,34 L158,46 C162,52 163,60 163,70 L163,226 C140,231 60,231 37,226 L37,70 C37,60 38,52 42,46 Z",
        sleeves: knitSleeves,
        ribs: knitCuffs + ["M80,34 C90,31 110,31 120,34 L122,39 C110,35 90,35 78,39 Z"],
        seams: knitSeams,
        folds: ["M68,60 C64,110 70,160 66,210", "M132,62 C136,112 130,162 134,210", "M100,50 C99,110 101,160 100,210"]
    )

    // MARK: Hoodie

    private static let hoodieSleeves = [
        "M40,48 C30,54 25,64 24,80 L18,218 C24,223 35,224 43,221 L46,100 C45,82 43,64 40,48 Z",
        "M160,48 C170,54 175,64 176,80 L182,218 C176,223 165,224 157,221 L154,100 C155,82 157,64 160,48 Z",
    ]
    private static let hoodieRibs = [
        "M35,213 L165,213 L165,228 C141,233 59,233 35,228 Z",
        "M19,205 L45,208 L43,221 C35,224 24,223 18,218 Z",
        "M181,205 L155,208 L157,221 C165,224 176,223 182,218 Z",
    ]

    static let hoodieFront = GarmentArt(
        body: "M80,36 C88,47 112,47 120,36 L160,48 C164,54 165,62 165,72 L165,228 C141,233 59,233 35,228 L35,72 C35,62 36,54 40,48 Z",
        sleeves: hoodieSleeves,
        under: "M78,38 C88,31 112,31 122,38 C112,48 88,48 78,38 Z",
        hood: "M72,42 C64,28 68,12 86,8 L114,8 C132,12 136,28 128,42 C116,30 84,30 72,42 Z",
        ribs: hoodieRibs,
        panels: [
            ("M62,148 L138,148 L150,196 L50,196 Z", 0.035),
            ("M80,36 C76,46 80,56 92,60 L96,55 C88,52 84,45 85,38 Z", -0.12),
            ("M120,36 C124,46 120,56 108,60 L104,55 C112,52 116,45 115,38 Z", -0.12),
        ],
        seams: ["M62,148 L52,186", "M138,148 L148,186", "M46,100 C45,82 43,64 40,48", "M154,100 C155,82 157,64 160,48"],
        stitches: ["M64,151 L136,151", "M51,193 L149,193"],
        folds: ["M68,64 C64,110 70,140 66,148", "M132,66 C136,110 130,140 134,148", "M100,62 C98,100 102,130 100,148", "M31,84 C29,130 31,170 28,206", "M169,84 C171,130 169,170 172,206", "M76,198 C74,204 76,208 74,212", "M124,198 C126,204 124,208 126,212"],
        cords: ["M92,50 C91,72 89,88 90,104", "M108,50 C109,72 111,88 110,104"]
    )

    static let hoodieBack = GarmentArt(
        body: "M80,36 C90,32 110,32 120,36 L160,48 C164,54 165,62 165,72 L165,228 C141,233 59,233 35,228 L35,72 C35,62 36,54 40,48 Z",
        sleeves: hoodieSleeves,
        ribs: hoodieRibs,
        panels: [("M76,36 C66,50 64,82 80,110 C88,120 112,120 120,110 C136,82 134,50 124,36 C112,30 88,30 76,36 Z", -0.06)],
        seams: ["M100,32 L100,118", "M46,100 C45,82 43,64 40,48", "M154,100 C155,82 157,64 160,48"],
        stitches: ["M80,108 C90,116 110,116 120,108"],
        folds: ["M70,120 C66,160 72,190 68,212", "M130,120 C134,160 128,190 132,212", "M31,84 C29,130 31,170 28,206", "M169,84 C171,130 169,170 172,206"]
    )

    // MARK: Shirt

    private static let shirtSleeves = [
        "M40,47 C30,53 26,63 25,78 L21,204 L45,206 L47,98 C46,80 44,63 40,47 Z",
        "M160,47 C170,53 174,63 175,78 L179,204 L155,206 L153,98 C154,80 156,63 160,47 Z",
    ]
    private static let shirtCuffs: [(d: String, t: Double)] = [
        ("M21,204 L45,206 L45,218 C37,220 28,220 21,217 Z", -0.05),
        ("M179,204 L155,206 L155,218 C163,220 172,220 179,217 Z", -0.05),
    ]
    private static let shirtHem = "M39,230 C54,239 76,238 100,234 C124,238 146,239 161,230"

    static let shirtFront = GarmentArt(
        body: "M80,34 C88,40 112,40 120,34 L160,47 C164,53 165,60 165,70 L163,232 C150,244 124,242 100,238 C76,242 50,244 37,232 L35,70 C35,60 36,53 40,47 Z",
        sleeves: shirtSleeves,
        under: "M80,34 C90,29 110,29 120,34 L120,39 C110,34 90,34 80,39 Z",
        panels: shirtCuffs + [
            ("M96,46 L104,46 L104,238 L96,238 Z", -0.03),
            ("M55,84 L87,84 L87,118 L71,124 L55,118 Z", 0.02),
            ("M113,84 L145,84 L145,118 L129,124 L113,118 Z", 0.02),
            ("M54,81 L88,81 L88,92 L71,96 L54,92 Z", -0.06),
            ("M112,81 L146,81 L146,92 L129,96 L112,92 Z", -0.06),
            ("M100,48 L80,34 C78,42 74,52 69,62 L90,64 Z", 0.04),
            ("M100,48 L120,34 C122,42 126,52 131,62 L110,64 Z", 0.04),
        ],
        seams: ["M96,64 L96,238", "M104,64 L104,238", "M47,98 C46,80 44,63 40,47", "M153,98 C154,80 156,63 160,47"],
        stitches: ["M57,116 L71,121 L85,116", "M115,116 L129,121 L143,116", shirtHem],
        folds: ["M66,128 C62,170 68,200 62,234", "M134,128 C138,170 132,200 138,234", "M31,90 C29,130 31,170 28,200", "M169,90 C171,130 169,170 172,200"],
        buttons: [CGPoint(x: 100, y: 72), CGPoint(x: 100, y: 102), CGPoint(x: 100, y: 132), CGPoint(x: 100, y: 162), CGPoint(x: 100, y: 192), CGPoint(x: 100, y: 222), CGPoint(x: 71, y: 92), CGPoint(x: 129, y: 92)]
    )

    static let shirtBack = GarmentArt(
        body: "M80,34 C90,30 110,30 120,34 L160,47 C164,53 165,60 165,70 L163,232 C150,244 124,242 100,238 C76,242 50,244 37,232 L35,70 C35,60 36,53 40,47 Z",
        sleeves: shirtSleeves,
        panels: shirtCuffs + [
            ("M80,34 C90,30 110,30 120,34 L122,41 C110,36 90,36 78,41 Z", 0.03),
            ("M40,47 L80,34 C90,30 110,30 120,34 L160,47 C162,56 163,62 164,68 C130,74 70,74 36,68 C37,62 38,56 40,47 Z", 0.025),
        ],
        seams: ["M36,68 C70,74 130,74 164,68", "M97,72 L97,238", "M103,72 L103,238"],
        stitches: [shirtHem],
        folds: ["M70,90 C66,150 72,200 66,234", "M130,90 C134,150 128,200 134,234", "M31,90 C29,130 31,170 28,200", "M169,90 C171,130 169,170 172,200"]
    )

    // MARK: Jacket

    private static let jacketSleeves = [
        "M38,48 C28,54 24,64 23,80 L19,218 C26,222 37,222 44,219 L46,100 C45,82 42,64 38,48 Z",
        "M162,48 C172,54 176,64 177,80 L181,218 C174,222 163,222 156,219 L154,100 C155,82 158,64 162,48 Z",
    ]
    private static let jacketBody = "M80,34 C88,40 112,40 120,34 L162,48 C166,54 167,61 167,72 L166,230 L34,230 L33,72 C33,61 34,54 38,48 Z"

    static let jacketFront = GarmentArt(
        body: jacketBody,
        sleeves: jacketSleeves,
        under: "M80,34 C90,30 110,30 120,34 L122,40 C110,35 90,35 78,40 Z",
        panels: [
            ("M100,58 L106,58 L106,230 L100,230 Z", -0.07),
            ("M112,86 L142,86 L142,118 L112,118 Z", 0.025),
            ("M46,152 L88,152 L88,198 L46,198 Z", 0.025),
            ("M112,152 L154,152 L154,198 L112,198 Z", 0.025),
            ("M100,58 L80,34 C72,40 64,50 58,64 L90,72 Z", -0.04),
            ("M100,58 L120,34 C128,40 136,50 142,64 L110,72 Z", -0.04),
        ],
        seams: ["M100,58 L100,230", "M46,100 C45,82 42,64 38,48", "M154,100 C155,82 158,64 162,48"],
        stitches: ["M114,88 L140,88 L140,116 L114,116 Z", "M48,154 L86,154 L86,196 L48,196 Z", "M114,154 L152,154 L152,196 L114,196 Z", "M35,224 L165,224", "M22,208 L44,210", "M178,208 L156,210"],
        folds: ["M70,74 C66,110 72,130 68,150", "M130,122 C134,136 130,146 132,150", "M68,200 C66,212 70,220 66,228", "M30,92 C28,140 30,180 27,214", "M170,92 C172,140 170,180 173,214"],
        buttons: [CGPoint(x: 106, y: 84), CGPoint(x: 106, y: 118), CGPoint(x: 106, y: 152), CGPoint(x: 106, y: 186), CGPoint(x: 106, y: 218)]
    )

    static let jacketBack = GarmentArt(
        body: "M80,34 C90,30 110,30 120,34 L162,48 C166,54 167,61 167,72 L166,230 L34,230 L33,72 C33,61 34,54 38,48 Z",
        sleeves: jacketSleeves,
        panels: [("M80,34 C90,30 110,30 120,34 L126,46 C110,39 90,39 74,46 Z", -0.04)],
        seams: ["M36,76 C70,82 130,82 164,76", "M46,100 C45,82 42,64 38,48", "M154,100 C155,82 158,64 162,48"],
        stitches: ["M35,224 L165,224", "M36,80 C70,86 130,86 164,80"],
        folds: ["M70,90 C66,150 72,196 68,228", "M130,90 C134,150 128,196 132,228", "M30,92 C28,140 30,180 27,214", "M170,92 C172,140 170,180 173,214"]
    )

    // MARK: Coat

    private static let coatSleeves = [
        "M36,50 C26,56 22,66 21,82 L16,240 C23,244 34,244 42,241 L45,104 C44,86 40,66 36,50 Z",
        "M164,50 C174,56 178,66 179,82 L184,240 C177,244 166,244 158,241 L155,104 C156,86 160,66 164,50 Z",
    ]

    static let coatFront = GarmentArt(
        body: "M80,34 C88,40 112,40 120,34 L164,50 C168,56 169,63 169,74 L174,294 L26,294 L31,74 C31,63 32,56 36,50 Z",
        sleeves: coatSleeves,
        under: "M80,34 C90,28 110,28 120,34 L118,42 C110,37 90,37 82,42 Z",
        panels: [
            ("M100,128 L106,128 L106,294 L100,294 Z", -0.06),
            ("M100,128 L80,34 C74,44 70,56 66,72 L76,78 L70,90 Z", 0.045),
            ("M100,128 L120,34 C126,44 130,56 134,72 L124,78 L130,90 Z", 0.045),
            ("M42,206 L84,206 L84,217 L42,217 Z", -0.05),
            ("M116,206 L158,206 L158,217 L116,217 Z", -0.05),
        ],
        seams: ["M100,128 L100,294", "M45,104 C44,86 40,66 36,50", "M155,104 C156,86 160,66 164,50", "M42,217 L84,217", "M116,217 L158,217"],
        stitches: ["M28,288 L172,288"],
        folds: ["M60,96 C56,170 64,230 54,292", "M140,96 C144,170 136,230 146,292", "M84,140 C82,200 86,250 82,292", "M28,96 C26,150 28,200 24,236", "M172,96 C174,150 172,200 176,236"],
        buttons: [CGPoint(x: 112, y: 146), CGPoint(x: 112, y: 180), CGPoint(x: 112, y: 214)]
    )

    static let coatBack = GarmentArt(
        body: "M80,34 C90,30 110,30 120,34 L164,50 C168,56 169,63 169,74 L174,294 L26,294 L31,74 C31,63 32,56 36,50 Z",
        sleeves: coatSleeves,
        panels: [
            ("M80,34 C90,30 110,30 120,34 L124,48 C110,41 90,41 76,48 Z", 0.04),
            ("M100,232 L106,232 L106,294 L100,294 Z", -0.07),
        ],
        seams: ["M100,44 L100,294", "M45,104 C44,86 40,66 36,50", "M155,104 C156,86 160,66 164,50"],
        stitches: ["M28,288 L172,288"],
        folds: ["M62,96 C58,170 66,230 56,292", "M138,96 C142,170 134,230 144,292", "M28,96 C26,150 28,200 24,236", "M172,96 C174,150 172,200 176,236"]
    )

    // MARK: Folded / shelf pieces (ClosetWise originals)

    static let trousers = GarmentArt(
        body: "M58,40 L142,40 L146,62 C150,130 156,210 160,296 L110,298 L100,104 L90,298 L40,296 C44,210 50,130 54,62 Z",
        ribs: ["M58,40 L142,40 L143,54 L57,54 Z"],
        panels: [("M60,56 L84,56 C80,70 72,76 62,78 Z", -0.06), ("M140,56 L116,56 C120,70 128,76 138,78 Z", -0.06)],
        seams: ["M100,54 L100,104", "M74,60 C70,150 66,230 64,296", "M126,60 C130,150 134,230 136,296"],
        stitches: ["M42,288 L88,289", "M112,289 L158,288", "M100,58 C104,72 104,86 100,98"],
        folds: ["M66,120 C62,180 58,240 56,292", "M134,120 C138,180 142,240 144,292", "M96,140 C94,200 94,250 92,292", "M104,140 C106,200 106,250 108,292"],
        buttons: [CGPoint(x: 100, y: 47)]
    )

    static let skirt = GarmentArt(
        body: "M66,44 L134,44 L136,58 C150,120 166,200 176,268 C130,280 70,280 24,268 C34,200 50,120 64,58 Z",
        ribs: ["M66,44 L134,44 L136,58 L64,58 Z"],
        panels: [("M76,60 L90,60 L74,274 L52,272 Z", -0.05), ("M110,60 L124,60 L148,272 L126,274 Z", -0.05)],
        seams: ["M82,58 L62,272", "M100,58 L100,276", "M118,58 L138,272", "M70,58 L42,268", "M130,58 L158,268"],
        stitches: ["M28,262 C70,272 130,272 172,262"],
        folds: ["M90,70 C84,150 80,210 76,270", "M110,70 C116,150 120,210 124,270"]
    )

    static let shorts = GarmentArt(
        body: "M56,60 L144,60 L146,74 C150,104 154,134 156,160 L110,166 L100,118 L90,166 L44,160 C46,134 50,104 54,74 Z",
        ribs: ["M56,60 L144,60 L145,72 L55,72 Z"],
        panels: [("M58,74 L82,74 C78,86 70,92 60,94 Z", -0.06), ("M142,74 L118,74 C122,86 130,92 140,94 Z", -0.06)],
        seams: ["M100,72 L100,118"],
        stitches: ["M46,152 L90,158", "M110,158 L154,152", "M100,76 C104,88 104,100 100,110"],
        folds: ["M70,100 C66,124 64,140 60,158", "M130,100 C134,124 136,140 140,158"],
        buttons: [CGPoint(x: 100, y: 66)]
    )

    static let shoes = GarmentArt(
        body: "M16,72 C16,54 40,44 70,46 C102,48 128,58 156,62 C178,65 188,74 186,86 L18,88 Z",
        ribs: ["M14,86 L188,86 L188,93 C150,98 50,98 14,93 Z"],
        panels: [("M66,48 C84,58 108,64 132,60 L134,68 C108,72 82,66 62,56 Z", -0.12)],
        seams: ["M70,56 C90,66 112,70 132,66"],
        stitches: ["M20,82 L184,82"],
        folds: ["M40,60 C60,66 80,70 100,70"]
    )
}
