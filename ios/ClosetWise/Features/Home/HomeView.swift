import SwiftUI

/// Screen 0 · Home: one thing to do today, a few numbers, and a nudge when there's one worth giving.
struct HomeView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showSettings = false

    private var todaysLog: OutfitLog? { store.logs.last { Calendar.current.isDateInToday($0.date) } }
    private var suggestion: Outfit? { store.suggestions(limit: 1).first }
    private var idleCoats: [WardrobeItem] { store.items.filter { $0.category == .outerwear && ($0.daysSinceWorn ?? 0) >= 60 } }
    private var avgCostPerWear: String {
        let values = store.items.compactMap(\.costPerWear)
        guard !values.isEmpty else { return "—" }
        return (values.reduce(0, +) / Decimal(values.count)).dollars
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !Cloud.shared.isSignedIn || Cloud.shared.lastError != nil { CloudStatusRow() }
                if SupabaseService.isConfigured && !GeminiKey.shared.isSet { geminiKeyRow }

                if store.items.isEmpty {
                    emptyCard
                } else {
                    todayCard
                    stats
                    if store.items.count < 5 { growRow }
                    if !idleCoats.isEmpty { nudge }
                    styleRow
                }
            }
            .padding(Theme.pad)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: Sections

    private var geminiKeyRow: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "key").foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your Gemini API key").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("AI reads of photos, purchase verdicts and outfit logging need it. Settings → Gemini API key.")
                        .font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(14)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UserProfile.greeting()).font(.subheadline).foregroundStyle(Theme.secondaryText)
                Text(store.profile.firstName.isEmpty ? "Welcome back" : store.profile.firstName)
                    .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { showSettings = true } label: {
                Circle().fill(Theme.primary).frame(width: 42, height: 42)
                    .overlay(Text(store.profile.initials).font(.subheadline.weight(.semibold)).foregroundStyle(.white))
            }
            .accessibilityLabel("Settings")
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hanger").font(.system(size: 30)).foregroundStyle(Theme.primary)
            Text("Let's fill your closet").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("Add a few pieces you wear a lot. ClosetWise uses them to check purchases and suggest outfits.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            PrimaryButton(title: "Add your first piece", systemImage: "camera") { router.tab = .add }
            Button("Or explore with a demo closet") { store.loadDemo(account: Cloud.shared.accountID) }
                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var todayCard: some View {
        if let log = todaysLog {
            VStack(alignment: .leading, spacing: 12) {
                Label("Today's outfit is logged", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                // Scrolls sideways so a 5-piece outfit can't make the whole page wider than the screen.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let name = log.photo, let image = ClosetStore.photo(name) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 56, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(log.itemIDs.compactMap(store.item).prefix(5)) { ItemImage(item: $0).frame(width: 56, height: 56) }
                    }
                }
                NavigationLink { LogOutfitView() } label: {
                    Text("Log another").font(.subheadline.weight(.medium))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 20))
        } else if let outfit = suggestion {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text("TODAY").font(.caption.weight(.bold)).foregroundStyle(Theme.secondaryText)
                    if let now = store.weather {
                        Text("·").foregroundStyle(Theme.secondaryText)
                        Label(now.headline, systemImage: now.symbol)
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    OutfitBoard(outfit: outfit, size: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(outfit.title).font(.headline).foregroundStyle(Theme.ink)
                        Text(outfit.reason).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(4)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        store.logOutfit(outfit.pieces.map(\.id), reaction: nil, source: .suggested)
                    } label: {
                        Text("Wear this").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.white).background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    NavigationLink { LogOutfitView() } label: {
                        Label("Log my own", systemImage: "camera").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(Theme.primary)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary))
                    }
                }
                Button { router.tab = .outfits } label: {
                    Label("More outfits", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.primary)
                }
            }
            .padding(16)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 20))
        } else {
            NavigationLink { LogOutfitView() } label: {
                Label("Log today's outfit", systemImage: "camera")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            MiniStat(value: "\(store.items.count)", label: store.items.count == 1 ? "piece" : "pieces")
            MiniStat(value: avgCostPerWear, label: "per wear")
            MiniStat(value: store.savedBySkipping.dollars, label: "saved", accent: true)
        }
    }

    private var nudge: some View {
        Button {
            router.closetFilter = .outerwear
            router.tab = .closet
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -12) {
                    ForEach(idleCoats.prefix(2)) { ItemImage(item: $0).frame(width: 36, height: 40) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(idleCoats.count) coat\(idleCoats.count == 1 ? "" : "s") unworn for 2+ months")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text("Worth a look before buying another").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }

    /// Shown while the closet is small: outfit ideas and checks get better with more pieces.
    private var growRow: some View {
        let kinds = Set(store.items.map(\.category))
        let missing = [(ItemCategory.top, "a top"), (.bottom, "a bottom"), (.shoes, "shoes")].filter { !kinds.contains($0.0) }.map(\.1)
        return Button { router.tab = .add } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep filling your closet").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(missing.isEmpty ? "More pieces mean sharper checks and outfit ideas" : "Add \(ListFormatter.localizedString(byJoining: missing)) to unlock outfit ideas")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private var styleRow: some View {
        NavigationLink { StyleProfileView() } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your style").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(store.styleTags.prefix(3).joined(separator: " · ").ifEmpty("Log outfits so ClosetWise can learn it"))
                        .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }
}

private struct MiniStat: View {
    let value: String, label: String
    var accent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(accent ? Theme.primary : Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

#Preview { NavigationStack { HomeView() }.environment(ClosetStore.preview).environment(AppRouter()) }

/// "More outfits →": text first, icon after.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
