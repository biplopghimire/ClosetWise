import AVFoundation
import SwiftUI

/// What the guide outline is shaped like, and what ClosetWise assumes the piece is if it
/// can't read the photo.
enum CaptureGuide: String, CaseIterable, Identifiable {
    case top, outerwear, pants, shorts, skirt, dress, shoes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "Top"
        case .outerwear: "Jacket"
        case .pants: "Pants"
        case .shorts: "Shorts"
        case .skirt: "Skirt"
        case .dress: "Dress"
        case .shoes: "Shoes"
        }
    }

    var category: ItemCategory {
        switch self {
        case .top: .top
        case .outerwear: .outerwear
        case .pants, .shorts, .skirt: .bottom
        case .dress: .dress
        case .shoes: .shoes
        }
    }

    var kind: GarmentKind {
        switch self {
        case .top: .tee
        case .outerwear: .jacket
        case .pants: .trousers
        case .shorts: .shorts
        case .skirt, .dress: .skirt
        case .shoes: .shoes
        }
    }

    /// Frame width and height as fractions of the screen width — the same shape every time,
    /// so every photo of this type is framed the same way.
    var frame: CGSize {
        switch self {
        case .top: CGSize(width: 0.86, height: 0.92)
        case .outerwear: CGSize(width: 0.88, height: 1.02)
        case .pants: CGSize(width: 0.62, height: 1.25)
        case .shorts: CGSize(width: 0.78, height: 0.72)
        case .skirt: CGSize(width: 0.72, height: 0.9)
        case .dress: CGSize(width: 0.66, height: 1.3)
        case .shoes: CGSize(width: 0.86, height: 0.5)
        }
    }

    /// Height ÷ width of the outline.
    var aspect: CGFloat {
        if self == .dress { return 1.9 }
        let box = GarmentSilhouette.bounds(kind)
        return box.width > 0 ? box.height / box.width : 1
    }

    var tip: String {
        switch self {
        case .shoes: "Side view, toe pointing left, on a plain floor"
        case .pants, .shorts, .skirt: "Lay it flat, waistband at the top"
        case .dress: "Lay it flat, neckline at the top"
        default: "Lay it flat, collar at the top, sleeves out"
        }
    }
}

/// Full-screen camera with a ghost outline of the chosen garment type. Fill the outline and
/// shoot: the photo is cropped to the frame, so every piece comes out framed the same way.
struct GuidedCamera: View {
    var start: CaptureGuide = .top
    let onCapture: (UIImage, CaptureGuide) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()
    @State private var guide: CaptureGuide = .top
    @State private var flash = false

    var body: some View {
        GeometryReader { geo in
            let frame = guideRect(in: geo.size)
            ZStack {
                Color.black
                CameraPreview(session: camera.session)
                // Dim everything outside the frame.
                Color.black.opacity(0.55)
                    .mask {
                        Rectangle()
                            .overlay { RoundedRectangle(cornerRadius: 22).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY).blendMode(.destinationOut) }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                ghost(frame)
                    .animation(.snappy, value: guide)
                controls
                if flash { Color.white.transition(.opacity).allowsHitTesting(false) }
                if camera.denied { deniedNotice }
            }
            .ignoresSafeArea()
            .onChange(of: camera.captured) { _, image in
                guard let image else { return }
                let cropped = Self.crop(image, to: frame, screen: geo.size) ?? image
                onCapture(cropped, guide)
                dismiss()
            }
        }
        .onAppear {
            guide = start
            camera.start()
        }
        .onDisappear { camera.stop() }
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: guide)
    }

    /// The outline frame, in the space between the tip at the top and the type chips below.
    private func guideRect(in size: CGSize) -> CGRect {
        let top: CGFloat = 165, bottom = size.height - 215
        var w = size.width * guide.frame.width
        var h = w * guide.aspect * 1.12   // outline plus breathing room
        if h > bottom - top {   // tall pieces on short screens: shrink, keeping the shape
            let fit = (bottom - top) / h
            w *= fit
            h *= fit
        }
        return CGRect(x: (size.width - w) / 2, y: (top + bottom) / 2 - h / 2, width: w, height: h)
    }

    private func ghost(_ frame: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
            Group {
                if guide == .dress {
                    DressOutline().fill(.white.opacity(0.22))
                        .overlay(DressOutline().stroke(.white.opacity(0.7), lineWidth: 1.5))
                } else {
                    GarmentSilhouette(kind: guide.kind).fill(.white.opacity(0.22))
                        .overlay(GarmentSilhouette(kind: guide.kind).stroke(.white.opacity(0.75), lineWidth: 1.5))
                }
            }
            .padding(frame.width * 0.05)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("Close camera")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)

            Text(guide.tip)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
                .contentTransition(.opacity)

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CaptureGuide.allCases) { option in
                        Button { withAnimation(.snappy) { guide = option } } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(guide == option ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(guide == option ? Color.white : Color.white.opacity(0.18), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Button {
                withAnimation(.easeOut(duration: 0.12)) { flash = true }
                withAnimation(.easeOut(duration: 0.3).delay(0.12)) { flash = false }
                camera.capture()
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 62, height: 62)
                }
            }
            .disabled(!camera.ready)
            .accessibilityLabel("Take photo")
            .padding(.bottom, 44)
        }
    }

    private var deniedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("ClosetWise needs the camera to photograph your clothes.").multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(32)
    }

    /// Crops the photo to the guide frame (plus a little margin). The preview fills the screen
    /// the same way the photo does (both 4:3, aspect-fill), so screen points map straight onto it.
    static func crop(_ image: UIImage, to frame: CGRect, screen: CGSize) -> UIImage? {
        let upright = image.uprighted()
        let px = upright.size
        let scale = max(screen.width / px.width, screen.height / px.height)
        let origin = CGPoint(x: (screen.width - px.width * scale) / 2, y: (screen.height - px.height * scale) / 2)
        let margin = frame.insetBy(dx: -frame.width * 0.06, dy: -frame.height * 0.06)
        var rect = CGRect(x: (margin.minX - origin.x) / scale, y: (margin.minY - origin.y) / scale,
                          width: margin.width / scale, height: margin.height / scale)
        rect = rect.intersection(CGRect(origin: .zero, size: px))
        guard !rect.isNull, rect.width > 50, rect.height > 50,
              let cg = upright.cgImage?.cropping(to: rect.applying(CGAffineTransform(scaleX: upright.scale, y: upright.scale))) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A garment drawing's outline, scaled to fill the rect and centred.
struct GarmentSilhouette: Shape {
    let kind: GarmentKind

    static func path(_ kind: GarmentKind) -> Path {
        var path = Path()
        for d in GarmentArtLibrary.art(kind, back: false).silhouette { path.addPath(SVGPath.path(d)) }
        return path
    }

    static func bounds(_ kind: GarmentKind) -> CGRect { path(kind).boundingRect }

    func path(in rect: CGRect) -> Path {
        let shape = Self.path(kind)
        let box = shape.boundingRect
        guard box.width > 0, box.height > 0 else { return shape }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let x = rect.midX - box.midX * scale, y = rect.midY - box.midY * scale
        return shape.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
    }
}

/// Simple dress outline for the guide (there's no dress drawing).
private struct DressOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x + w * 0.36, y: y))
        p.addLine(to: CGPoint(x: x + w * 0.4, y: y + h * 0.1))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.6, y: y + h * 0.1), control: CGPoint(x: x + w * 0.5, y: y + h * 0.16))
        p.addLine(to: CGPoint(x: x + w * 0.64, y: y))
        p.addLine(to: CGPoint(x: x + w * 0.72, y: y + h * 0.04))
        p.addLine(to: CGPoint(x: x + w * 0.68, y: y + h * 0.36))
        p.addLine(to: CGPoint(x: x + w * 0.95, y: y + h))
        p.addLine(to: CGPoint(x: x + w * 0.05, y: y + h))
        p.addLine(to: CGPoint(x: x + w * 0.32, y: y + h * 0.36))
        p.addLine(to: CGPoint(x: x + w * 0.28, y: y + h * 0.04))
        p.closeSubpath()
        return p
    }
}

// MARK: - Camera

@MainActor
@Observable
final class CameraModel: NSObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private(set) var ready = false
    private(set) var denied = false
    private(set) var captured: UIImage?

    func start() {
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: break
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
            default:
                denied = true
                return
            }
            configure()
        }
    }

    func stop() {
        let session = session
        Task.detached { session.stopRunning() }
    }

    func capture() {
        guard ready else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func configure() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo   // 4:3, same as the preview
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        let session = session
        Task.detached {
            session.startRunning()
            await MainActor.run { self.ready = true }
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        Task { @MainActor in self.captured = image }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

extension UIImage {
    /// The same picture with its orientation applied, so pixel (0,0) is the top-left you see.
    func uprighted() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
