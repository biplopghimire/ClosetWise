import SwiftUI

/// Garment drawings rendered once into images, with their soft shadow baked in.
///
/// Drawing a garment live (paths, blurs, knit textures, gradients) costs tens of milliseconds —
/// fine for one piece, too much for a feed of outfit cards. Each piece is drawn once per size it
/// appears at; a card is then just a few cached pictures, so scrolling the feed draws nothing new.
@MainActor
final class GarmentSprites {
    static let shared = GarmentSprites()
    /// Room around the garment for its shadow.
    static let pad: CGFloat = 8

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()
    private let scale = min(2, UIScreen.main.scale)

    func cached(_ item: WardrobeItem, size: CGSize) -> UIImage? { cache.object(forKey: key(item, size)) }

    /// The garment's picture at this size, drawing it the first time it's needed.
    @discardableResult
    func image(_ item: WardrobeItem, size: CGSize) -> UIImage? {
        if let hit = cached(item, size: size) { return hit }
        let pad = Self.pad
        let content = GarmentCanvas(kind: item.kind, color: item.swatch)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 2, y: 4)
            .padding(pad)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        let bytes = Int((size.width + 2 * pad) * (size.height + 2 * pad) * scale * scale * 4)
        cache.setObject(image, forKey: key(item, size), cost: bytes)
        return image
    }

    /// Draws every piece of the closet at its card size, one per run-loop turn, before the feed needs them.
    func prerender(_ items: [WardrobeItem], cardSize: CGFloat) async {
        for item in items {
            if Task.isCancelled { return }
            let size = OutfitBoard.slot(for: item.category, size: cardSize)
            if cached(item, size: size) == nil {
                image(item, size: size)
                await Task.yield()
            }
        }
    }

    private func key(_ item: WardrobeItem, _ size: CGSize) -> NSString {
        "\(item.kind.rawValue)|\(item.hex)|\(Int(size.width))x\(Int(size.height))" as NSString
    }
}

/// A cached garment picture sized to sit where the live drawing would.
struct GarmentSprite: View {
    let item: WardrobeItem
    let size: CGSize
    private let image: UIImage?

    init(item: WardrobeItem, size: CGSize) {
        self.item = item
        self.size = size
        image = GarmentSprites.shared.image(item, size: size)
    }

    var body: some View {
        if let image {
            Image(uiImage: image).resizable()
                .frame(width: size.width + 2 * GarmentSprites.pad, height: size.height + 2 * GarmentSprites.pad)
                .frame(width: size.width, height: size.height)
        } else {
            GarmentCanvas(kind: item.kind, color: item.swatch).frame(width: size.width, height: size.height)
        }
    }
}

/// An outfit card for the feed: the board (built from cached garment pictures) plus title and reason.
struct OutfitIdeaCard: View {
    let outfit: Outfit
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OutfitBoard(outfit: outfit, size: size, sprites: true)
            Text(outfit.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text(outfit.reason)
                .font(.caption).foregroundStyle(Theme.secondaryText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: size)
    }
}
