import PhotosUI
import SwiftUI

/// What we've learned from your outfits, plus a place to show us your style yourself.
/// Both go to Gemini as context for suggestions and purchase checks.
struct StyleProfileView: View {
    @Environment(ClosetStore.self) private var store
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var geminiTask: GeminiTask?
    @State private var justUpdated = false
    @State private var section: Section = .see

    private enum Section: String, CaseIterable { case see = "What we see", tell = "Tell us" }

    var body: some View {
        @Bindable var store = store
        let learned = store.learned

        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch section {
                case .see:
                    noticed(learned)
                        .id("summary")
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.primary, lineWidth: justUpdated ? 2 : 0))
                    geminiSection(proxy)
                    if learned.outfitCount > 0 {
                        colorsWorn(learned)
                        fitsWorn(learned)
                        if !learned.signaturePieces.isEmpty { signature(learned) }
                    }
                case .tell:
                    Text("ClosetWise reads this alongside what you actually wear, so suggestions and purchase checks feel like you.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    vibes($store.preferences)
                    inYourWords($store.preferences)
                    fitPreferences($store.preferences)
                    colorPreferences($store.preferences)
                    dressiness($store.preferences)
                    occasions($store.preferences)
                    inspiration
                }
            }
            .padding(Theme.pad)
        }
        }
        .navigationTitle("Your style")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.preferences) { store.save() }
        .onChange(of: photoSelection) { _, picks in
            Task {
                for pick in picks {
                    if let data = try? await pick.loadTransferable(type: Data.self) { store.addInspiration(data) }
                }
                photoSelection = []
            }
        }
    }

    // MARK: Learned

    private func noticed(_ learned: LearnedStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What we've noticed", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                Text("From \(learned.outfitCount) outfits").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.ink)
            Text(store.geminiSummary?.summary ?? learned.summary)
                .font(.subheadline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = store.geminiSummary?.fitNotes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            FlowLayout(spacing: 6) {
                ForEach(store.geminiSummary?.tags ?? learned.tags, id: \.self) { tag in
                    Text(tag).font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white, in: Capsule())
                }
            }
            Text(store.geminiSummary == nil ? "Learned on your phone from logged outfits" : "Tailored by ClosetWise · \(store.geminiSummary!.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func colorsWorn(_ learned: LearnedStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Colours you wear")
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(learned.colors.prefix(7), id: \.self) { c in
                        Rectangle().fill(swatch(c.value)).frame(width: max(4, g.size.width * c.share - 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 22)
            Text(learned.colors.prefix(4).map { "\($0.value.capitalized) \(Int(($0.share * 100).rounded()))%" }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private func fitsWorn(_ learned: LearnedStyle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How you wear things", trailing: "Fit by category")
            ForEach([ItemCategory.top, .bottom, .outerwear, .shoes].filter { learned.fits[$0] != nil }) { cat in
                let fits = learned.fits[cat] ?? []
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(cat.filterTitle).font(.subheadline)
                        Spacer()
                        if let top = fits.first {
                            let cut = learned.silhouettes[cat]?.first.map { ", \($0.value)" } ?? ""
                            Text("Mostly \(top.value.rawValue)\(cut)").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    FitBar(fits: fits)
                }
            }
        }
    }

    private func signature(_ learned: LearnedStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Signature pieces", trailing: "Worn most lately")
            HStack(spacing: 10) {
                ForEach(learned.signaturePieces) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        ItemImage(item: item).aspectRatio(0.9, contentMode: .fit)
                        Text(item.name).font(.caption2).lineLimit(1)
                        Text(item.fitDescription).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: Expressed

    private func vibes(_ prefs: Binding<StylePreferences>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Your vibe", trailing: "Pick any")
            FlowLayout(spacing: 6) {
                ForEach(StylePreferences.vibeOptions, id: \.self) { vibe in
                    Button { prefs.wrappedValue.vibes.toggle(vibe) } label: { Chip(title: vibe, selected: prefs.wrappedValue.vibes.contains(vibe)) }
                }
            }
        }
    }

    private func inYourWords(_ prefs: Binding<StylePreferences>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "In your words")
            TextField("e.g. Clean basics, wide-leg everything, one statement piece. Nothing too tight.", text: prefs.about, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        }
    }

    private func fitPreferences(_ prefs: Binding<StylePreferences>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Fit you like", trailing: "Tap again to clear")
            ForEach([ItemCategory.top, .bottom, .outerwear], id: \.self) { cat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(cat.filterTitle).font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FitType.allCases) { fit in
                                let on = prefs.wrappedValue.fits[cat.rawValue] == fit
                                Button { prefs.wrappedValue.fits[cat.rawValue] = on ? nil : fit } label: { Chip(title: fit.label, selected: on) }
                                    .accessibilityHint(fit.blurb)
                            }
                        }
                    }
                }
            }
        }
    }

    private func colorPreferences(_ prefs: Binding<StylePreferences>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            swatchPicker(title: "Colours you love", selection: prefs.loveColors, other: prefs.avoidColors)
            swatchPicker(title: "Colours you avoid", selection: prefs.avoidColors, other: prefs.loveColors)
        }
    }

    private func swatchPicker(title: String, selection: Binding<[String]>, other: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(StylePreferences.palette, id: \.name) { c in
                    let on = selection.wrappedValue.contains(c.name)
                    Button {
                        selection.wrappedValue.toggle(c.name)
                        other.wrappedValue.removeAll { $0 == c.name }
                    } label: {
                        Circle().fill(Color(hex: c.hex))
                            .overlay(Circle().stroke(Theme.border))
                            .overlay(Circle().stroke(Theme.primary, lineWidth: on ? 2.5 : 0).padding(-3))
                            .overlay { if on { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(c.hex > 0xA00000 ? Theme.ink : .white) } }
                            .frame(height: 30)
                    }
                    .accessibilityLabel("\(c.name)\(on ? ", selected" : "")")
                }
            }
        }
    }

    private func dressiness(_ prefs: Binding<StylePreferences>) -> some View {
        let value = Binding<Double>(
            get: { Double(prefs.wrappedValue.dressiness ?? Int(store.learned.formality.rounded())) },
            set: { prefs.wrappedValue.dressiness = Int($0.rounded()) }
        )
        let current = prefs.wrappedValue.dressiness ?? Int(store.learned.formality.rounded())
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "How dressed up, usually", trailing: StylePreferences.dressinessLabels[max(0, min(4, current - 1))])
            Slider(value: value, in: 1...5, step: 1)
            HStack {
                Text("Lounge"); Spacer(); Text("Formal")
            }
            .font(.caption2).foregroundStyle(Theme.secondaryText)
        }
    }

    private func occasions(_ prefs: Binding<StylePreferences>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "What you dress for")
            FlowLayout(spacing: 6) {
                ForEach(StylePreferences.occasionOptions, id: \.self) { o in
                    Button { prefs.wrappedValue.occasions.toggle(o) } label: { Chip(title: o, selected: prefs.wrappedValue.occasions.contains(o)) }
                }
            }
        }
    }

    private var inspiration: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Inspiration", trailing: "Up to 6 photos")
            Text("Looks you love — outfits you've saved, people whose style you like. ClosetWise uses them to get a feel for your taste.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(store.preferences.inspirationFiles, id: \.self) { name in
                    Color.clear
                        .aspectRatio(0.8, contentMode: .fit)
                        .overlay {
                            if let image = store.inspirationImage(name) {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) { store.removeInspiration(name) }
                        }
                }
                if store.preferences.inspirationFiles.count < 6 {
                    PhotosPicker(selection: $photoSelection, maxSelectionCount: 6 - store.preferences.inspirationFiles.count, matching: .images) {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                            .aspectRatio(0.8, contentMode: .fit)
                            .overlay(Label("Add", systemImage: "plus").font(.caption.weight(.medium)).foregroundStyle(Theme.primary))
                    }
                }
            }
        }
    }

    private func geminiSection(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            if let task = geminiTask {
                GeminiProgressView(task: task, expectedSeconds: 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            PrimaryButton(title: geminiTask?.isRunning == true ? "Working…" : "Have ClosetWise size up my style", systemImage: "sparkles") {
                run(proxy)
            }
            .disabled(geminiTask?.isRunning == true)
            .opacity(geminiTask?.isRunning == true ? 0.6 : 1)
        }
        .padding(.top, 4)
    }

    private func run(_ proxy: ScrollViewProxy) {
        let task = StyleService.makeTask(photoCount: min(6, store.preferences.inspirationFiles.count))
        withAnimation { geminiTask = task }
        task.begin()
        Task {
            do {
                try await StyleService.refreshSummary(store, progress: task)
                task.succeed("Updated — your summary is at the top.")
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo("summary", anchor: .top) }
                withAnimation(.easeInOut(duration: 0.3).delay(0.5)) { justUpdated = true }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { justUpdated = false }
            } catch {
                task.fail(error.localizedDescription)
            }
        }
    }

    private func swatch(_ color: String) -> Color {
        if let hex = StylePreferences.palette.first(where: { $0.name == color })?.hex { return Color(hex: hex) }
        if let item = store.items.first(where: { $0.color.lowercased() == color }) { return item.swatch }
        return Theme.secondaryText
    }
}

/// Stacked bar of fit shares, tight → oversized.
struct FitBar: View {
    let fits: [Weighted<FitType>]

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(fits.sorted { $0.value.ease < $1.value.ease }, id: \.self) { f in
                    Rectangle()
                        .fill(Theme.primary.opacity(0.25 + 0.75 * Double(f.value.ease) / 5))
                        .frame(width: max(3, g.size.width * f.share - 2))
                        .overlay {
                            if f.share > 0.18 {
                                Text(f.value.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(f.value.ease >= 3 ? .white : Theme.ink)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel(fits.map { "\($0.value.label) \(Int(($0.share * 100).rounded())) percent" }.joined(separator: ", "))
    }
}

extension Array where Element: Equatable {
    mutating func toggle(_ value: Element) {
        if let i = firstIndex(of: value) { remove(at: i) } else { append(value) }
    }
}

#Preview { NavigationStack { StyleProfileView() }.environment(ClosetStore.preview).environment(AppRouter()) }
