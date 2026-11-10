import SwiftUI

/// The endless grid of outfit ideas. Kept in its own view so new pages only redraw the grid,
/// not the clothing rail and shelves above it.
struct OutfitIdeasFeed: View {
    let feed: OutfitFeed
    let cardWidth: CGFloat
    let hasCloset: Bool
    let hasWeather: Bool
    let onSelect: (Outfit) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), alignment: .top)]

    var body: some View {
        if feed.empty || !hasCloset {
            Text(hasWeather && hasCloset
                 ? "Nothing in your closet suits today's weather yet — add a few pieces for it."
                 : "Outfit ideas appear once you have a top, a bottom and shoes.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        } else {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(feed.rounds) { round in
                    Section {
                        ForEach(round.entries) { entry in
                            Button { onSelect(entry.outfit) } label: { OutfitIdeaCard(outfit: entry.outfit, size: cardWidth) }
                                .buttonStyle(.plain)
                                .id(entry.id)
                                .onAppear { if feed.shouldLoadMore(after: entry) { feed.loadMore() } }
                        }
                    } header: {
                        if round.id > 0 { RoundDivider() }
                    }
                }
            }
            // Draw each piece of the closet once, up front; every card after that is just pictures.
            .task(id: cardWidth) {
                await GarmentSprites.shared.prerender(feed.pieces, cardSize: cardWidth)
            }

            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
                .onAppear { feed.loadMore() }
        }
    }
}

/// Marks where the feed starts going round again.
private struct RoundDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Label("Mixed up again", systemImage: "shuffle")
                .font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                .fixedSize()
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityLabel("You've seen every outfit your closet makes. Here they are again in a new order.")
    }
}
