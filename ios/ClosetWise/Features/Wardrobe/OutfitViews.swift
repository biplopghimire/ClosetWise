import SwiftUI

/// Flat-lay composition of an outfit's pieces.
struct OutfitBoard: View {
    let outfit: Outfit
    var size: CGFloat = 200

    var body: some View {
        let s = size
        ZStack {
            if let layer = outfit.layer {
                GarmentCanvas(kind: layer.kind, color: layer.swatch)
                    .frame(width: s * 0.5, height: s * 0.78)
                    .rotationEffect(.degrees(-6))
                    .offset(x: -s * 0.2, y: -s * 0.04)
            }
            GarmentCanvas(kind: outfit.bottom.kind, color: outfit.bottom.swatch)
                .frame(width: s * 0.4, height: s * 0.62)
                .offset(x: s * 0.12, y: s * 0.17)
            GarmentCanvas(kind: outfit.top.kind, color: outfit.top.swatch)
                .frame(width: s * 0.44, height: s * 0.68)
                .offset(x: outfit.layer == nil ? -s * 0.08 : s * 0.04, y: -s * 0.12)
            GarmentCanvas(kind: outfit.shoes.kind, color: outfit.shoes.swatch)
                .frame(width: s * 0.3, height: s * 0.17)
                .offset(x: -s * 0.24, y: s * 0.36)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, x: 2, y: 4)
        .frame(width: s, height: s)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .accessibilityElement()
        .accessibilityLabel(outfit.pieces.map(\.name).joined(separator: ", "))
    }
}

struct OutfitCard: View {
    let outfit: Outfit
    var size: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OutfitBoard(outfit: outfit, size: size)
            Text(outfit.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(outfit.reason)
                .font(.caption).foregroundStyle(Theme.secondaryText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: size)
    }
}

struct OutfitDetailView: View {
    let outfit: Outfit
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var loved: Bool { store.lovedCombos.contains(outfit.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OutfitBoard(outfit: outfit, size: 300).frame(maxWidth: .infinity)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outfit.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(outfit.reason).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button {
                        store.react(to: outfit, loved ? .fine : .loved)
                        if loved { store.lovedCombos.remove(outfit.id); store.save() }
                    } label: {
                        Image(systemName: loved ? "heart.fill" : "heart")
                            .font(.title2).foregroundStyle(Theme.primary)
                    }
                    .accessibilityLabel(loved ? "Unlove this look" : "Love this look")
                }

                SectionHeader(title: "\(outfit.pieces.count) pieces you already own")
                ForEach(outfit.pieces) { item in
                    HStack(spacing: 12) {
                        ItemImage(item: item).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            Text("\(item.fitDescription) · \(wearLine(item))").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Wear this today", systemImage: "checkmark") {
                        store.logOutfit(outfit.pieces.map(\.id), reaction: loved ? .loved : nil, source: .suggested)
                        dismiss()
                    }
                    SecondaryButton(title: "Not for me") {
                        store.react(to: outfit, .notMe)
                        dismiss()
                    }
                }
                .padding(.top, 8)
                Text("Wearing it logs the outfit and updates your style. \"Not for me\" stops suggesting this combination.")
                    .font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            .padding(Theme.pad)
        }
    }

    private func wearLine(_ item: WardrobeItem) -> String {
        var parts = ["Worn \(item.wearCount)×"]
        if let days = item.daysSinceWorn { parts.append(days >= 30 ? "not worn in \(days) days" : "last worn \(days)d ago") }
        return parts.joined(separator: " · ")
    }
}
