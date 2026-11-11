import SwiftUI

struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.semibold))
                .foregroundStyle(accent ? Theme.primary : Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct Chip: View {
    let title: String
    var selected = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(selected ? .white : Theme.ink)
            .background(selected ? Theme.primary : .clear, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : Theme.border))
    }
}

/// Square garment tile with a mint background, as in the wardrobe grid.
struct ItemTile: View {
    let item: WardrobeItem
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemImage(item: item)
                .aspectRatio(0.9, contentMode: .fit)
            Text(caption ?? item.name)
                .font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
    }
}

struct ItemImage: View {
    let item: WardrobeItem
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.mint)
            .overlay(
                GeometryReader { g in
                    let inset = min(g.size.width, g.size.height) * 0.1
                    if let name = item.photo, let image = ClosetStore.photo(name) {
                        // Multiply drops a plain white backdrop when the cutout couldn't run.
                        Image(uiImage: image).resizable().scaledToFit()
                            .blendMode(.multiply)
                            .padding(inset)
                            .frame(width: g.size.width, height: g.size.height)
                    } else {
                        GarmentCanvas(kind: item.kind, color: item.swatch)
                            .padding(inset)
                            .offset(y: item.kind == .shoes ? 0 : -inset * 0.4)
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
            )
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Theme.primary)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary))
        }
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// The item's photo when it has one, otherwise its drawn garment (no background).
struct ItemArtwork: View {
    let item: WardrobeItem
    var body: some View {
        if let name = item.photo, let image = ClosetStore.photo(name) {
            Image(uiImage: image).resizable().scaledToFit().blendMode(.multiply)
        } else {
            GarmentCanvas(kind: item.kind, color: item.swatch)
        }
    }
}

/// One piece on an outfit board: its real photo when there is one, otherwise the drawn garment.
/// Cut-out photos sit on the board like the drawings; photos that still have their background
/// show as small rounded tiles so they don't look like pasted rectangles.
struct GarmentPiece: View {
    let item: WardrobeItem

    var body: some View {
        if let name = item.photo, let image = ClosetStore.photo(name) {
            if ClosetStore.isCutout(name) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
                    .padding(4)
            }
        } else {
            GarmentCanvas(kind: item.kind, color: item.swatch)
        }
    }
}

/// The ClosetWise logo (the app icon artwork), with iOS's rounded-square corners.
struct AppLogo: View {
    var size: CGFloat = 72

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: size * 0.08, y: size * 0.05)
            .accessibilityLabel("ClosetWise")
    }
}
