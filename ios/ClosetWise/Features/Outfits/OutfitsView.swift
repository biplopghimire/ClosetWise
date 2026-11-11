import SwiftUI

/// The Outfits tab: build a look one row at a time.
///
/// Each row is a piece of the outfit (layer, top, bottom or dress, shoes, accessory). Swipe a row
/// to change just that piece; lock a row and Shuffle finds the best look around it. Occasion chips
/// set how dressed up it should be.
struct OutfitsView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var builder = OutfitBuilder()
    @State private var logged = false

    private var outfit: Outfit? { builder.outfit }
    private var loved: Bool { outfit.map { store.lovedCombos.contains($0.id) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if builder.canBuild, let outfit {
                    occasionChips
                    if builder.hasDresses && builder.hasSeparates { modePicker }
                    VStack(spacing: 14) {
                        ForEach(builder.rows) { row in
                            SlotRow(row: row, height: Self.height(for: row.slot),
                                    position: position(for: row.slot),
                                    locked: builder.locked.contains(row.slot)) {
                                withAnimation(.snappy) { builder.toggleLock(row.slot) }
                            }
                        }
                    }
                    summary(outfit)
                } else {
                    emptyState
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { if builder.canBuild && outfit != nil { actionBar } }
        .overlay(alignment: .top) { if logged { loggedToast } }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: outfit?.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: builder.shuffles)
        .sensoryFeedback(.success, trigger: logged) { _, new in new }
        .onAppear {
            builder.configure(items: store.items, signals: store.outfitSignals)
            startFromRouter()
        }
        .onChange(of: store.items) { builder.configure(items: store.items, signals: store.outfitSignals) }
        .onChange(of: store.preferences) { builder.configure(items: store.items, signals: store.outfitSignals) }
        .onChange(of: router.outfitStart) { startFromRouter() }
    }

    private func startFromRouter() {
        guard let item = router.outfitStart else { return }
        router.outfitStart = nil
        withAnimation(.snappy) { builder.start(with: store.item(item.id) ?? item) }
    }

    private func position(for slot: OutfitSlot) -> Binding<UUID?> {
        Binding(
            get: { builder.selection[slot] },
            set: { id in
                builder.selection[slot] = id
                builder.select(slot, entry: id)
            }
        )
    }

    /// Card height per row: a body-shaped stack, shoes small, tops and dresses big.
    static func height(for slot: OutfitSlot) -> CGFloat {
        switch slot {
        case .layer: 116
        case .top: 132
        case .dress: 200
        case .bottom: 150
        case .shoes: 78
        case .accessory: 64
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ScreenTitle(text: "Outfits")
            Spacer()
            if let weather = store.weather {
                Label("\(WeatherNow.degrees(weather.dressForC)) · \(weather.headline)", systemImage: weather.symbol)
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            } else if WeatherService.shared.access != .denied {
                Button { Task { await WeatherService.shared.requestAccess() } } label: {
                    Label("Use weather", systemImage: "cloud.sun").font(.caption.weight(.medium))
                }
                .disabled(WeatherService.shared.loading)
            }
        }
        .padding(.horizontal, Theme.pad)
    }

    private var occasionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Occasion.allCases) { occasion in
                    let selected = (builder.occasion ?? .everyday) == occasion
                    Button {
                        withAnimation(.snappy) { builder.setOccasion(occasion == .everyday ? nil : occasion) }
                    } label: { Chip(title: occasion.title, selected: selected) }
                }
            }
            .padding(.horizontal, Theme.pad)
        }
    }

    private var modePicker: some View {
        Picker("Outfit type", selection: Binding(get: { builder.mode }, set: { mode in withAnimation(.snappy) { builder.setMode(mode) } })) {
            Text("Separates").tag(OutfitBuilder.Mode.separates)
            Text("Dress").tag(OutfitBuilder.Mode.dress)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .padding(.horizontal, Theme.pad)
    }

    private func summary(_ outfit: Outfit) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StyleMeter(score: outfit.styleScore)
            VStack(alignment: .leading, spacing: 4) {
                Text(outfit.title).font(.headline).foregroundStyle(Theme.ink)
                Text(outfit.reason).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, Theme.pad)
        .animation(.snappy, value: outfit.id)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { builder.shuffle() }
            } label: {
                Label("Shuffle", systemImage: "dice")
                    .symbolEffect(.bounce, value: builder.shuffles)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Theme.primary)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.primary))
            }
            .accessibilityHint("Finds another outfit that keeps your locked pieces")

            Button {
                guard let outfit else { return }
                store.react(to: outfit, loved ? .fine : .loved)
                if loved { store.lovedCombos.remove(outfit.id); store.save() }
            } label: {
                Image(systemName: loved ? "heart.fill" : "heart")
                    .symbolEffect(.bounce, value: loved)
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 50, height: 50)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }
            .accessibilityLabel(loved ? "Unlove this look" : "Love this look")

            Menu {
                Button("Not for me", systemImage: "hand.thumbsdown") {
                    guard let outfit else { return }
                    store.react(to: outfit, .notMe)
                    withAnimation(.snappy) { builder.shuffle() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 50)
            }
            .accessibilityLabel("More")

            Button {
                guard let outfit else { return }
                store.logOutfit(outfit.pieces.map(\.id), reaction: loved ? .loved : nil, source: .suggested)
                withAnimation(.spring) { logged = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation(.easeOut) { logged = false }
                }
            } label: {
                Label("Wear today", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var loggedToast: some View {
        Label("Logged for today", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.primary, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tshirt").font(.system(size: 34)).foregroundStyle(Theme.primary)
            Text("Build outfits from your closet").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("Add a top, a bottom and shoes (or a dress and shoes), and ClosetWise puts them together.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            PrimaryButton(title: "Add pieces", systemImage: "camera") { router.tab = .add }
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, Theme.pad)
    }
}

// MARK: - Row

/// One piece of the outfit: swipe sideways through every piece that fits this slot.
private struct SlotRow: View {
    let row: OutfitBuilder.Row
    let height: CGFloat
    @Binding var position: UUID?
    let locked: Bool
    let toggleLock: () -> Void
    /// Off while the row is placing itself, so layout settling isn't mistaken for a swipe.
    @State private var settled = false
    /// The last piece the user swiped to, to tell their swipes apart from Shuffle's picks.
    @State private var swipedTo: UUID?

    private var scrollBinding: Binding<UUID?> {
        Binding(get: { position }, set: { id in
            guard settled else { return }
            swipedTo = id
            position = id
        })
    }

    private var cardWidth: CGFloat { height * (row.slot == .shoes || row.slot == .accessory ? 1.4 : 0.9) }
    private var current: OutfitBuilder.Entry? { row.entries.first { $0.id == position } }
    private var index: Int { row.entries.firstIndex { $0.id == position } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.slot.title.uppercased())
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondaryText)
                Text(current?.item?.name ?? "None")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer()
                Text("\(index + 1)/\(row.entries.count)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                Button(action: toggleLock) {
                    Image(systemName: locked ? "lock.fill" : "lock.open")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(locked ? .white : Theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(locked ? Theme.primary : Theme.mint, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(locked ? "Unlock \(row.slot.title.lowercased())" : "Lock \(row.slot.title.lowercased())")
                .accessibilityHint("Locked pieces stay when you shuffle")
            }
            .padding(.horizontal, Theme.pad)

            // Measured before the cards lay out, so the chosen piece starts centred.
            GeometryReader { geo in
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(row.entries) { entry in
                            card(entry)
                                .frame(width: cardWidth, height: height)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.78)
                                        .opacity(phase.isIdentity ? 1 : 0.4)
                                        .rotation3DEffect(.degrees(phase.value * -18), axis: (x: 0, y: 1, z: 0))
                                }
                                .id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: scrollBinding)
                .contentMargins(.horizontal, max(0, (geo.size.width - cardWidth) / 2), for: .scrollContent)
                .scrollDisabled(locked)
                .onAppear { recentre(proxy) }
                // Shuffle reorders the row: put the new pick in the middle again.
                .onChange(of: row.entries.map(\.id)) { recentre(proxy) }
                // Shuffle (or a mode switch) picked a different piece: scroll to it.
                .onChange(of: position) { _, new in if new != swipedTo { recentre(proxy) } }
                }
            }
            .frame(height: height)
            .overlay {
                if locked {
                    RoundedRectangle(cornerRadius: 14).stroke(Theme.primary, lineWidth: 2)
                        .frame(width: cardWidth + 6, height: height + 6)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.slot.title): \(current?.item?.name ?? "none")")
            .accessibilityAdjustableAction { direction in
                let next = direction == .increment ? min(index + 1, row.entries.count - 1) : max(index - 1, 0)
                withAnimation(.snappy) { position = row.entries[next].id }
            }
        }
    }

    /// The first layout pass places rows before their margins settle; centre the pick after it,
    /// and only then start listening to the scroll position.
    private func recentre(_ proxy: ScrollViewProxy) {
        settled = false
        let target = position
        swipedTo = target
        DispatchQueue.main.async {
            withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { settled = true }
        }
    }

    @ViewBuilder private func card(_ entry: OutfitBuilder.Entry) -> some View {
        if let item = entry.item {
            ItemImage(item: item)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "nosign").foregroundStyle(Theme.secondaryText)
                        Text("No \(row.slot.title.lowercased())").font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                }
        }
    }
}

// MARK: - Style meter

/// How much the look is "you", as a ring.
private struct StyleMeter: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle().stroke(Theme.primary.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(score)))
                Text("you").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 52, height: 52)
        .animation(.snappy, value: score)
        .accessibilityElement()
        .accessibilityLabel("\(score) percent your style")
    }
}
