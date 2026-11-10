import PhotosUI
import SwiftUI
import os

/// Screen 4 · Check a purchase — from a link, a photo/screenshot, or details typed in.
struct CheckPurchaseView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var link = ""
    @State private var progress: GeminiTask?
    @State private var confirm: ConfirmRequest?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @FocusState private var linkFocused: Bool
    private var busy: Bool { progress?.isRunning == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Check a purchase")
                    Text("See how it fits your closet and your style before you buy.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }

                if store.items.count < 3 { emptyClosetTip }

                inputCard

                if let progress {
                    GeminiProgressView(task: progress, expectedSeconds: 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !store.purchases.isEmpty { recentChecks }
            }
            .padding(Theme.pad)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .task { debugCheckLinkIfRequested() }
        #endif
        .navigationDestination(item: $confirm) { request in
            ConfirmProductView(request: request) { confirm = nil }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { await read(image) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await read(image) } }.ignoresSafeArea()
        }
    }

    // MARK: Sections

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Theme.secondaryText)
                TextField(text: $link, prompt: Text(verbatim: "Paste a product link")) { Text("Product link") }
                    .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    .focused($linkFocused)
                    .submitLabel(.go).onSubmit(checkLink)
                if link.isEmpty {
                    Button("Paste") { link = UIPasteboard.general.string ?? "" }
                        .font(.subheadline.weight(.medium))
                } else {
                    Button { link = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText) }
                        .accessibilityLabel("Clear link")
                }
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))

            if !link.isEmpty {
                PrimaryButton(title: busy ? "Working…" : "Check this item") { checkLink() }
                    .disabled(busy)
            }

            HStack(spacing: 8) {
                SourceButton(icon: "camera", title: "Camera") { showCamera = true }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    SourceLabel(icon: "photo", title: "Photo")
                }
                SourceButton(icon: "square.and.pencil", title: "Type it") {
                    confirm = ConfirmRequest(item: AttributeGuesser.guess(ProductDraft()), source: .manual)
                }
            }
            .disabled(busy)

            Menu {
                ForEach(SampleData.exampleProducts) { product in
                    Button(product.name) { confirm = ConfirmRequest(item: product, source: .example) }
                }
            } label: {
                Label("Try an example", systemImage: "sparkles").font(.caption.weight(.medium))
            }
        }
        .padding(14)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyClosetTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb").foregroundStyle(Theme.primary)
            Text("Checks are much more useful once your closet has a few pieces.")
                .font(.caption).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("Add") { router.tab = .add }.font(.caption.weight(.semibold))
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var recentChecks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent checks")
            ForEach(store.purchases.prefix(4)) { record in
                HStack(spacing: 12) {
                    ItemImage(item: record.product).frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.product.name).font(.subheadline).lineLimit(1)
                        Text(record.verdict).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if let decision = record.decision {
                        Text(decision.rawValue)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(decision == .skipped ? Theme.primary : Theme.ink)
                            .background(decision == .skipped ? Theme.mint : Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Actions

    #if DEBUG
    /// Link-check testing: `-checkLink <url>` runs a check on launch and logs what came back.
    private func debugCheckLinkIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-checkLink"), i + 1 < args.count, link.isEmpty else { return }
        link = args[i + 1]
        checkLink()
    }
    #endif

    private func checkLink() {
        guard !link.isEmpty, !busy else { return }
        linkFocused = false
        let task = ItemReader.linkTask()
        withAnimation { progress = task }
        task.begin()
        Task {
            do {
                let started = Date()
                let (item, source) = try await ItemReader.read(link: link, store: store, task: task)
                #if DEBUG
                Logger(subsystem: "app.closetwise", category: "links").notice(
                    "LINKCHECK ok \(String(format: "%.1f", Date().timeIntervalSince(started)), privacy: .public)s source=\(String(describing: source), privacy: .public) name=\(item.name, privacy: .public) kind=\(item.kind.rawValue, privacy: .public) color=\(item.color, privacy: .public) fit=\(item.fit.rawValue, privacy: .public) cut=\(item.silhouette ?? "-", privacy: .public) material=\(item.material, privacy: .public) price=\(item.price.map { "\($0)" } ?? "-", privacy: .public) photo=\(item.photo != nil, privacy: .public)")
                #endif
                await open(ConfirmRequest(item: item, source: source))
            } catch {
                #if DEBUG
                Logger(subsystem: "app.closetwise", category: "links").notice("LINKCHECK failed: \(error.localizedDescription, privacy: .public)")
                #endif
                task.fail(error.localizedDescription)
            }
        }
    }

    private func read(_ image: UIImage) async {
        let task = ItemReader.photoTask()
        withAnimation { progress = task }
        task.begin()
        let (item, source) = await ItemReader.read(photo: image, store: store, task: task)
        await open(ConfirmRequest(item: item, source: source))
    }

    /// Leaves the finished progress on screen for a moment, then opens the confirm screen.
    private func open(_ request: ConfirmRequest) async {
        try? await Task.sleep(for: .seconds(0.6))
        confirm = request
        try? await Task.sleep(for: .seconds(0.6))
        withAnimation { progress = nil }
    }
}

private struct SourceButton: View {
    let icon: String, title: String, action: () -> Void
    var body: some View { Button(action: action) { SourceLabel(icon: icon, title: title) }.buttonStyle(.plain) }
}

private struct SourceLabel: View {
    let icon: String, title: String
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct ConfirmRequest: Identifiable, Hashable {
    enum Source: Hashable {
        case link(String), photo, gemini, manual, example
        var note: String {
            switch self {
            case .link(let host): "Read from \(host). Fit and type are guessed from the listing — check them."
            case .photo: "Colour read from your photo. Fill in the rest so the check is accurate."
            case .gemini: "ClosetWise read these details. Fix anything it got wrong."
            case .manual: "Fill in what you know — type, colour and fit matter most."
            case .example: "An example product. Change anything to see how the check responds."
            }
        }
    }
    let id = UUID()
    var item: WardrobeItem
    var source: Source
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Average colour of a (cut-out) photo, mapped to the nearest palette name.
enum DominantColor {
    /// Works on cut-outs (transparent background) and on plain photos: the background colour
    /// is estimated from the image border and pixels close to it are ignored.
    static func of(_ image: UIImage) -> (name: String, hex: UInt32)? {
        let side = 64
        guard let cg = image.cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        func pixel(_ i: Int) -> (hex: UInt32, alpha: UInt8) {
            let a = px[i * 4 + 3]
            guard a > 0 else { return (0, 0) }
            func ch(_ v: UInt8) -> UInt32 { UInt32(min(255, Double(v) * 255 / Double(a))) }
            return (ch(px[i * 4]) << 16 | ch(px[i * 4 + 1]) << 8 | ch(px[i * 4 + 2]), a)
        }

        // Background = most common opaque border colour (if the border is opaque at all).
        var border: [UInt32] = []
        for i in 0..<side {
            for idx in [i, (side - 1) * side + i, i * side, i * side + side - 1] {
                let p = pixel(idx)
                if p.alpha > 200 { border.append(p.hex) }
            }
        }
        let background: UInt32? = border.count > side * 2
            ? border.max { a, b in border.filter { ColorMath.deltaE($0, a) < 8 }.count < border.filter { ColorMath.deltaE($0, b) < 8 }.count }
            : nil

        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in 0..<(side * side) {
            let p = pixel(i)
            guard p.alpha > 128 else { continue }
            if let background, ColorMath.deltaE(p.hex, background) < 18 { continue }
            r += Double((p.hex >> 16) & 0xFF); g += Double((p.hex >> 8) & 0xFF); b += Double(p.hex & 0xFF); n += 1
        }
        guard n > 20 else { return nil }
        let hex = UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(b / n)
        let nearest = StylePreferences.palette.min { ColorMath.deltaE($0.hex, hex) < ColorMath.deltaE($1.hex, hex) }!
        return (nearest.name, hex)
    }
}

/// UIKit camera, for taking a photo of the item.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

#Preview { NavigationStack { CheckPurchaseView() }.environment(ClosetStore.preview).environment(AppRouter()) }
