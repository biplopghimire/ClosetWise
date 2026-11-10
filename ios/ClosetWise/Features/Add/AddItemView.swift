import PhotosUI
import SwiftUI

/// Add tab: photograph a piece (or pick one), ClosetWise fills in the details, you confirm.
struct AddItemView: View {
    @Environment(ClosetStore.self) private var store
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var progress: GeminiTask?
    @State private var confirm: ConfirmRequest?
    @State private var justAdded: String?

    private var recent: [WardrobeItem] { Array(store.items.suffix(6).reversed()) }
    private var busy: Bool { progress?.isRunning == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    ScreenTitle(text: "Add to your closet")
                    Text("Snap one piece at a time on a plain background. ClosetWise fills in the details.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }

                HStack(spacing: 12) {
                    BigAction(icon: "camera.fill", title: "Take a photo") { showCamera = true }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || busy)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        BigActionLabel(icon: "photo.on.rectangle", title: "From photos")
                    }
                    .disabled(busy)
                }

                Button {
                    confirm = ConfirmRequest(item: AttributeGuesser.guess(ProductDraft()), source: .manual)
                } label: {
                    Label("Or type it in", systemImage: "square.and.pencil").font(.subheadline.weight(.medium))
                }
                .disabled(busy)

                if let progress {
                    GeminiProgressView(task: progress, expectedSeconds: 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let justAdded {
                    Label("\(justAdded) is in your closet.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Theme.primary)
                        .transition(.opacity)
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Recently added", trailing: "\(store.items.count) in your closet")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                            ForEach(recent) { ItemTile(item: $0) }
                        }
                    }
                }
            }
            .padding(Theme.pad)
            .animation(.easeInOut(duration: 0.25), value: justAdded)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $confirm) { request in
            ConfirmProductView(request: request, mode: .addToCloset) {
                let name = store.items.last?.name ?? "It"
                confirm = nil
                withAnimation { justAdded = name; progress = nil }
            }
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

    private func read(_ image: UIImage) async {
        justAdded = nil
        let task = ItemReader.photoTask()
        withAnimation { progress = task }
        task.begin()
        let (item, source) = await ItemReader.read(photo: image, store: store, task: task)
        try? await Task.sleep(for: .seconds(0.6))
        confirm = ConfirmRequest(item: item, source: source)
    }
}

/// Large square button used for the main ways in.
struct BigAction: View {
    let icon: String, title: String, action: () -> Void
    var body: some View {
        Button(action: action) { BigActionLabel(icon: icon, title: title) }.buttonStyle(.plain)
    }
}

struct BigActionLabel: View {
    let icon: String, title: String
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.primary)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16))
        .opacity(enabled ? 1 : 0.45)
    }
}

#Preview { NavigationStack { AddItemView() }.environment(ClosetStore.preview).environment(AppRouter()) }
