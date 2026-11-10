import SwiftUI

/// Screen 6 · Compatible items
struct CompatibleItemsView: View {
    let product: WardrobeItem
    let compatible: [WardrobeItem]
    @State private var filter: ItemCategory?
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var categories: [ItemCategory] {
        ItemCategory.allCases.filter { c in compatible.contains { $0.category == c } }
    }
    private var items: [WardrobeItem] {
        guard let filter else { return compatible }
        return compatible.filter { $0.category == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pieces you own that pair well with the \(product.name.lowercased()) — matched on colour, dressiness and proportion.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button { filter = nil } label: { Chip(title: "All \(compatible.count)", selected: filter == nil) }
                            ForEach(categories) { c in
                                let n = compatible.filter { $0.category == c }.count
                                Button { filter = c } label: { Chip(title: "\(c.filterTitle) \(n)", selected: filter == c) }
                            }
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(items) { ItemTile(item: $0, caption: "\($0.name) · \($0.fit.rawValue)") }
                    }
                }
            }
            SecondaryButton(title: "Back to results") { dismiss() }
        }
        .padding(Theme.pad)
        .navigationTitle("Works with \(compatible.count) items")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { CompatibleItemsView(product: SampleData.exampleProducts[0], compatible: [SampleData.wideLegJeans, SampleData.loafers]) }
}
