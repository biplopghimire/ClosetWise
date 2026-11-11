import SwiftUI

/// The Outfits tab: build a look one row at a time.
///
/// Each row is a piece of the outfit (layer, top, bottom or dress, shoes, accessory). Swipe a row
/// to change just that piece; "ClosetWise pick" steps through the best distinct looks, and locking a
/// row re-ranks around it and marks suggested pieces with a sparkle. Occasion chips
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
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: .sectionHeaders) {
                header
                if builder.canBuild, let outfit {
                    occasionChips
                    if builder.hasDresses && builder.hasSeparates { modePicker }
                    // The summary strip pins to the top while the rows scroll under it.
                    Section {
                        ForEach(builder.rows) { row in
                            SlotRow(row: row, height: Self.height(for: row.slot),
                                    position: position(for: row.slot),
                                    locked: builder.locked.contains(row.slot),
                                    suggested: Set(builder.suggested[row.slot] ?? []),
                                    source: builder.suggestionSource) {
                                withAnimation(.snappy) { builder.toggleLock(row.slot) }
                            }
                        }
                    } header: {
                        SummaryStrip(outfit: outfit, pick: builder.pickIndex, loved: loved,
                                     love: toggleLove, dislike: dislike)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { if builder.canBuild && outfit != nil { actionBar } }
        // Solid status-bar area, so rows scrolling up don't show behind the clock.
        .overlay(alignment: .top) {
            Color.clear.frame(height: 0)
                .background(Color(.systemBackground).ignoresSafeArea(edges: .top))
        }
        .overlay(alignment: .top) { if logged { loggedToast } }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: outfit?.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: builder.pickCount)
        .sensoryFeedback(.success, trigger: logged) { _, new in new }
        .onAppear {
            builder.configure(items: store.items, signals: store.outfitSignals, profile: store.styleContext)
            startFromRouter()
        }
        .onChange(of: store.items) { builder.configure(items: store.items, signals: store.outfitSignals, profile: store.styleContext) }
        .onChange(of: store.preferences) { builder.configure(items: store.items, signals: store.outfitSignals, profile: store.styleContext) }
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
        case .layer: 92
        case .top: 112
        case .dress: 172
        case .bottom: 124
        case .shoes: 60
        case .accessory: 52
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

    private func toggleLove() {
        guard let outfit else { return }
        let wasLoved = loved
        store.react(to: outfit, wasLoved ? .fine : .loved)
        if wasLoved { store.lovedCombos.remove(outfit.id); store.save() }
    }

    private func dislike() {
        guard let outfit else { return }
        store.react(to: outfit, .notMe)
        withAnimation(.snappy) { builder.nextPick() }
    }

    /// "Next pick" walks ClosetWise's overall ranking. With a piece locked the ranking is about
    /// outfits built around it: "Style it" for the best one, then "Next match".
    private var pickButtonTitle: String {
        if builder.locked.isEmpty { return "Next pick" }
        return builder.pickIndex == nil ? "Style it" : "Next match"
    }

    /// Two clear actions: see ClosetWise's next pick, or wear this one.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { builder.nextPick() }
            } label: {
                Label(pickButtonTitle, systemImage: builder.locked.isEmpty ? "sparkles" : "wand.and.stars")
                    .symbolEffect(.bounce, value: builder.pickCount)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(Theme.primary)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(builder.picks.isEmpty)
            .accessibilityHint(builder.locked.isEmpty
                ? "Shows ClosetWise's next-best outfit, each one different from the last"
                : "Shows the next-best outfit that keeps your locked pieces")

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
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
    /// Pieces suggested to go with the locked ones (sparkle badge).
    var suggested: Set<UUID> = []
    var source: OutfitBuilder.SuggestionSource?
    let toggleLock: () -> Void
    /// Off while the row is placing itself, so layout settling isn't mistaken for a swipe.
    @State private var settled = false
    /// The last piece the user swiped to, to tell their swipes apart from ClosetWise picks.
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
        VStack(alignment: .leading, spacing: 4) {
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
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(locked ? .white : Theme.secondaryText)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle().inset(by: -8))
                        .background(locked ? Theme.primary : Theme.mint, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(locked ? "Unlock \(row.slot.title.lowercased())" : "Lock \(row.slot.title.lowercased())")
                .accessibilityHint("Locked pieces stay when you ask for the next pick")
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
                // A new pick reorders the row: put the new pick in the middle again.
                .onChange(of: row.entries.map(\.id)) { recentre(proxy) }
                // A new pick (or a mode switch) chose a different piece: scroll to it.
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
                .overlay(alignment: .topTrailing) {
                    if suggested.contains(item.id) { SuggestedBadge(source: source) }
                }
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
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(Theme.primary.opacity(0.15), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: Double(score)))
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: score)
        .accessibilityElement()
        .accessibilityLabel("\(score) percent your style")
    }
}

// MARK: - Suggested badge

/// Top-right sparkle on a piece suggested to go with the locked ones.
private struct SuggestedBadge: View {
    let source: OutfitBuilder.SuggestionSource?

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Theme.primary, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .padding(6)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(source == .gemini ? "Suggested by Gemini" : "Suggested by ClosetWise")
    }
}

// MARK: - Summary strip

/// Pinned at the top: how "you" the look is, which pick it is, and one line on why — plus love / not for me.
/// Tap to read the full reason.
private struct SummaryStrip: View {
    let outfit: Outfit
    let pick: Int?
    let loved: Bool
    let love: () -> Void
    let dislike: () -> Void
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 10) {
            StyleMeter(score: outfit.styleScore, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let pick {
                        Text("#\(pick + 1)")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                            .contentTransition(.numericText(value: Double(pick)))
                    }
                    Text(outfit.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(outfit.reason)
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }

            iconButton(loved ? "heart.fill" : "heart", tint: loved ? .pink : Theme.secondaryText, active: loved, action: love)
                .accessibilityLabel(loved ? "Unlove this look" : "Love this look")
            iconButton("hand.thumbsdown", tint: Theme.secondaryText, active: false, action: dislike)
                .accessibilityLabel("Not for me")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, 4)
        .animation(.snappy, value: outfit.id)
        .accessibilityElement(children: .contain)
    }

    private func iconButton(_ icon: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: active)
                .frame(width: 32, height: 32)
                .background(Color(.systemBackground).opacity(0.8), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
