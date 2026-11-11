import SwiftUI

/// Screen 3 · Wardrobe, shown as a closet: a hanging rail and a shelf for bottoms and shoes.
/// Outfits live in their own tab (`OutfitsView`).
struct ClosetView: View {
    @State private var filter: ItemCategory?
    @State private var selected: UUID?
    @State private var detail: WardrobeItem?

    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    private var items: [WardrobeItem] { store.items }
    private let filters: [ItemCategory] = [.top, .outerwear, .bottom, .shoes]

    private var hanging: [WardrobeItem] { items.filter { $0.kind.hangs && matches($0) } }
    private var shelved: [WardrobeItem] { items.filter { !$0.kind.hangs && matches($0) } }
    /// Upper shelf: trousers, skirts, shorts. Lower shelf: shoes and sandals.
    private var bottomShelf: [WardrobeItem] { shelved.filter { $0.kind != .shoes } }
    private var shoeShelf: [WardrobeItem] { shelved.filter { $0.kind == .shoes } }
    @State private var shelfWidth: CGFloat = 0
    private var selectedItem: WardrobeItem? { hanging.first { $0.id == selected } }

    private func matches(_ item: WardrobeItem) -> Bool { filter == nil || item.category == filter }

    var body: some View {
        Group {
            if items.isEmpty { emptyState } else { closet }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: applyRouterFilter)
        .onChange(of: router.closetFilter) { applyRouterFilter() }
    }

    private func applyRouterFilter() {
        guard let wanted = router.closetFilter else { return }
        filter = wanted
        selected = nil
        router.closetFilter = nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            GarmentCanvas(kind: .shirt, face: .side, color: Theme.border, hanger: .wood, headroom: 10)
                .frame(width: 90, height: 160).opacity(0.8)
            Text("Your closet is empty").font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            Text("Add pieces with a photo and they'll hang here.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            PrimaryButton(title: "Add a piece", systemImage: "camera") { router.tab = .add }
                .frame(maxWidth: 260)
            Button("Load the demo closet") { store.loadDemo(account: Cloud.shared.accountID) }.font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(Theme.pad)
    }

    private var closet: some View {
        ScrollViewReader { _ in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        ScreenTitle(text: "Your closet")
                        Spacer()
                        Text("\(items.count) piece\(items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button { withAnimation { filter = nil } } label: { Chip(title: "All", selected: filter == nil) }
                            ForEach(filters) { c in
                                Button { withAnimation { filter = c; selected = nil } } label: { Chip(title: c.filterTitle, selected: filter == c) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)

                if !hanging.isEmpty {
                    VStack(spacing: 4) {
                        ClothingRail(items: hanging, selected: $selected) { detail = $0 }
                            .id(filter)
                        caption.padding(.horizontal, Theme.pad)
                    }
                }

                if filter == nil || !shelved.isEmpty {
                    shelf
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
        }
        }
        .sheet(item: $detail) { item in
            GarmentDetailView(
                item: store.item(item.id) ?? item,   // live, so a photo picked after Buy shows straight away
                index: items.firstIndex(of: item) ?? 0,
                total: items.count,
                outfits: store.outfits(with: item)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var caption: some View {
        VStack(spacing: 3) {
            if let item = selectedItem {
                Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Text(wearSummary(item)).font(.caption).foregroundStyle(Theme.secondaryText)
                Text("Tap again to take it off the rail").font(.caption2).foregroundStyle(Theme.secondaryText.opacity(0.8))
            } else {
                Text("Tap a piece to turn it around").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Text(hanging.count > 3 ? "Scroll along the rail to see everything hanging" : "Tap it twice to see the details").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .multilineTextAlignment(.center)
        .animation(.easeInOut(duration: 0.25), value: selected)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 22) {
            if filter != .shoes {
                shelfRow(bottomShelf, label: "Bottoms", empty: "No bottoms yet", itemHeight: 104)
            }
            if filter != .bottom {
                shelfRow(shoeShelf, label: "Shoes", empty: "No shoes yet", itemHeight: 52)
            }
        }
    }

    /// One wooden shelf, full width, with its pieces standing on it and their names underneath.
    private func shelfRow(_ pieces: [WardrobeItem], label: String, empty: String, itemHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Theme.pad)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(pieces) { item in
                            Button { detail = item } label: {
                                // The real photo when there is one, otherwise the drawing.
                                ItemArtwork(item: item)
                                    .frame(width: 80, height: itemHeight)
                                    .shadow(color: .black.opacity(0.14), radius: 3, x: 1, y: 3)
                            }
                            .accessibilityLabel(item.name)
                        }
                        if pieces.isEmpty {
                            Text(empty).font(.caption).foregroundStyle(Theme.secondaryText.opacity(0.8))
                                .frame(height: itemHeight * 0.6, alignment: .bottom)
                        }
                    }
                    .padding(.horizontal, 10)
                    ShelfBoard().frame(height: 10)
                    HStack(spacing: 12) {
                        ForEach(pieces) { item in
                            Text(item.name).font(.caption2).foregroundStyle(Theme.secondaryText)
                                .lineLimit(1).frame(width: 80)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
                // The board spans the closet even when the shelf only holds a pair or two.
                .frame(minWidth: max(0, shelfWidth - 2 * (Theme.pad - 10)), alignment: .leading)
                .padding(.horizontal, Theme.pad - 10)
            }
        }
    }

    private func wearSummary(_ item: WardrobeItem) -> String {
        var parts = ["Worn \(item.wearCount)×"]
        if let cpw = item.costPerWear { parts.append("\(cpw.dollars) per wear") }
        if let days = item.daysSinceWorn, days >= 30 { parts.append("not worn in \(days) days") }
        return parts.joined(separator: " · ")
    }
}

private struct ShelfBoard: View {
    var body: some View {
        let oak = Color(hex: 0xB98A5E)
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [oak.mixed(0.25), oak, oak.mixed(-0.3)], startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 4)
    }
}

#Preview { NavigationStack { ClosetView() }.environment(ClosetStore.preview).environment(AppRouter()) }
