import PhotosUI
import SwiftUI

/// Screen 7 · Log today's outfit: photo → ClosetWise spots the pieces → confirm → save.
/// Saving bumps wear counts and teaches the style profile.
struct LogOutfitView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var prefill: [UUID] = []

    @State private var photo: UIImage?
    @State private var picked: [UUID] = []
    @State private var notInCloset: [String] = []
    @State private var reaction: OutfitLog.Reaction?
    @State private var progress: GeminiTask?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photoArea

                if let progress {
                    GeminiProgressView(task: progress, compact: progress.isFinished && progress.error == nil, expectedSeconds: 8)
                }

                piecesSection

                if !picked.isEmpty {
                    reactionSection
                }

                if let savedNote {
                    Label(savedNote, systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(Theme.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
                        .transition(.opacity)
                }
            }
            .padding(Theme.pad)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: savedNote == nil ? (picked.isEmpty ? "Add at least one piece" : "Save outfit") : "Saved") { save() }
                .disabled(picked.isEmpty || savedNote != nil || progress?.isRunning == true)
                .opacity(picked.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .navigationTitle("Today's outfit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { if picked.isEmpty { picked = prefill } }
        .sheet(isPresented: $showPicker) {
            ItemPickerSheet(exclude: Set(picked)) { id in picked.append(id) }
                .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { await detect(image) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await detect(image) } }.ignoresSafeArea()
        }
    }

    // MARK: Sections

    @ViewBuilder private var photoArea: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable().scaledToFit()
                .frame(height: 220).frame(maxWidth: .infinity)
                .background(Theme.mint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Button("Retake photo", systemImage: "camera") { showCamera = true }
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose another", systemImage: "photo") }
                        Button("Remove photo", systemImage: "trash", role: .destructive) { self.photo = nil; progress = nil }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.4)).padding(10)
                    }
                }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.viewfinder").font(.system(size: 34)).foregroundStyle(Theme.primary)
                Text("Snap today's outfit").font(.headline).foregroundStyle(Theme.ink)
                Text("A mirror selfie or your clothes laid out — ClosetWise spots the pieces.")
                    .font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(.white).background(Theme.primary, in: Capsule())
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Photos", systemImage: "photo").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(Theme.primary).overlay(Capsule().stroke(Theme.primary))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
        }
    }

    private var piecesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: picked.isEmpty ? "What are you wearing?" : "You're wearing", trailing: picked.isEmpty ? nil : "\(picked.count) piece\(picked.count == 1 ? "" : "s")")
            ForEach(picked, id: \.self) { id in
                if let item = store.item(id) {
                    HStack(spacing: 12) {
                        ItemImage(item: item).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.subheadline)
                            Text("Worn \(item.wearCount)× → \(item.wearCount + 1)×").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button { picked.removeAll { $0 == id } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText.opacity(0.6))
                        }
                        .accessibilityLabel("Remove \(item.name)")
                    }
                }
            }
            Button { showPicker = true } label: {
                Label(picked.isEmpty ? "Pick pieces from your closet" : "Add a piece it missed", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(store.items.isEmpty)
            if store.items.isEmpty {
                Text("Your closet is empty — add a few pieces first so ClosetWise can match them.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if !notInCloset.isEmpty {
                Text("Also spotted, not in your closet: \(notInCloset.joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var reactionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "How do you feel in it?")
            HStack(spacing: 8) {
                reactionButton(.loved, "Love it", "heart.fill")
                reactionButton(.fine, "It's fine", "hand.thumbsup")
                reactionButton(.notMe, "Not me", "hand.thumbsdown")
            }
        }
    }

    private func reactionButton(_ r: OutfitLog.Reaction, _ title: String, _ icon: String) -> some View {
        let on = reaction == r
        return Button { reaction = on ? nil : r } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(on ? .white : Theme.ink)
                .background(on ? Theme.primary : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : Theme.border))
        }
    }

    // MARK: Actions

    private func detect(_ image: UIImage) async {
        photo = image
        notInCloset = []
        guard !store.items.isEmpty else { return }
        let task = OutfitService.task()
        withAnimation { progress = task }
        task.begin()
        do {
            let found = try await OutfitService.detect(image, store: store, task: task)
            withAnimation {
                for id in found.itemIDs where !picked.contains(id) { picked.append(id) }
                notInCloset = found.notInCloset
            }
            task.succeed(found.itemIDs.isEmpty ? "Nothing matched your closet — pick the pieces below." : "Spotted \(found.itemIDs.count) of your pieces — check they're right.")
        } catch {
            task.fail(error.localizedDescription)
        }
    }

    private func save() {
        let before = Set(store.learned.tags)
        let photoName = photo.flatMap { store.savePhoto($0) }
        store.logOutfit(picked, reaction: reaction, photo: photoName)
        let new = store.learned.tags.filter { !before.contains($0) }
        withAnimation {
            savedNote = new.isEmpty
                ? "Saved. Wear counts and your style profile are updated."
                : "Saved. Your style now includes: \(new.joined(separator: ", "))."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
    }
}

/// Pick a closet item to add to an outfit.
struct ItemPickerSheet: View {
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exclude: Set<UUID>
    let onPick: (UUID) -> Void
    @State private var query = ""

    private var items: [WardrobeItem] {
        store.items.filter { !exclude.contains($0.id) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onPick(item.id)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ItemImage(item: item).frame(width: 40, height: 40)
                        VStack(alignment: .leading) {
                            Text(item.name).foregroundStyle(Theme.ink)
                            Text(item.fitDescription).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search your closet")
            .navigationTitle("Add a piece")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { NavigationStack { LogOutfitView() }.environment(ClosetStore.preview).environment(AppRouter()) }
