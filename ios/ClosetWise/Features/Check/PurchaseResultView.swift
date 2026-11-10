import SwiftUI

/// Screen 5 · Purchase check results: duplicates, style fit, compatibility, cost per wear.
struct PurchaseResultView: View {
    @Environment(ClosetStore.self) private var store
    let result: PurchaseCheckResult
    let onFinish: () -> Void

    @State private var gemini: PurchaseCheckService.Judgment?
    @State private var geminiTask: GeminiTask?
    @State private var showDuplicatesAll = false
    @State private var openTile: Tile?

    private enum Tile: String, Identifiable { case duplicates, style, outfits, cost; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                verdictCard
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    tile(.duplicates, label: "Look-alikes", value: result.duplicates.isEmpty ? "None" : "\(result.duplicates.count)",
                         detail: result.duplicates.first.map { "\($0.level) to your \($0.item.name.lowercased())" } ?? "Nothing like it in your closet",
                         good: result.duplicates.allSatisfy { $0.score < 0.7 })
                    tile(.style, label: "Your style", value: "\(result.styleFit.score)", detail: result.styleFit.label,
                         good: result.styleFit.score >= 55)
                    tile(.outfits, label: "Outfits", value: "\(result.outfits.count)",
                         detail: result.duplicates.isEmpty ? "with \(result.compatible.count) pieces you own" : "\(result.newOutfitCount) you can't make yet",
                         good: result.newOutfitCount >= 3)
                    tile(.cost, label: "Cost per wear", value: result.costPerWear.map { "≈\($0.dollars)" } ?? "—",
                         detail: "~\(Int(result.predictedWearsPerYear.rounded())) wears a year", good: true)
                }
                Text("You decide — this is just information.")
                    .font(.caption).foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity)
            }
            .padding(Theme.pad)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                SecondaryButton(title: "Skip") { finish(.skipped) }
                PrimaryButton(title: "Buy anyway") { finish(.bought) }
            }
            .padding(.horizontal, Theme.pad).padding(.vertical, 10)
            .background(.bar)
        }
        .sheet(item: $openTile) { tile in
            NavigationStack {
                ScrollView {
                    Group {
                        switch tile {
                        case .duplicates: duplicatesCard
                        case .style: styleCard
                        case .outfits: compatibilityCard
                        case .cost: costCard
                        }
                    }
                    .padding(Theme.pad)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { openTile = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
        .navigationTitle("Purchase check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard gemini == nil else { return }
            let task = PurchaseCheckService.makeTask(similar: min(5, result.duplicates.count), hasPhoto: result.product.photo != nil)
            geminiTask = task
            task.begin()
            let judgment = await PurchaseCheckService.judge(result, store: store, progress: task)
            withAnimation { gemini = judgment }
        }
    }

    private func finish(_ decision: PurchaseRecord.Decision) {
        store.record(result, decision: decision)
        // Bought from a store link: give the closet a photo of just the item (the check showed the listing's own).
        if decision == .bought, result.product.photoOptions != nil {
            let id = result.product.id
            Task { await ClosetPhotoPicker.improve(itemID: id, store: store) }
        }
        onFinish()
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            ItemImage(item: result.product).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.product.name).font(.subheadline.weight(.semibold))
                Text([result.product.price?.dollars, result.product.store].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                Text("\(result.product.fit.label) · \(result.product.color) · \(result.product.kind.label.lowercased())")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((gemini?.verdict ?? result.verdict.rawValue).uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(verdictColor)
            Text(gemini?.explanation ?? result.explanation).font(.subheadline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if gemini != nil {
                Label("ClosetWise tried it on against your closet and style", systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(Theme.secondaryText)
            } else if let geminiTask, SupabaseService.isConfigured, geminiTask.isRunning || geminiTask.error != nil {
                GeminiProgressView(task: geminiTask, compact: true, expectedSeconds: 8)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func tile(_ t: Tile, label: String, value: String, detail: String, good: Bool) -> some View {
        Button { openTile = t } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.secondaryText.opacity(0.6))
                }
                Text(value).font(.title2.weight(.bold)).foregroundStyle(good ? Theme.primary : Color(hex: 0xB5651D))
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private var verdictColor: Color {
        switch result.verdict {
        case .addsValue: Theme.primary
        case .consider: Theme.ink
        case .limitedGain, .probablySkip: Color(hex: 0xB5651D)
        }
    }

    private var duplicatesCard: some View {
        Card(label: "DUPLICATES") {
            if result.duplicates.isEmpty {
                headline("Nothing like it", good: true)
                Text("You don't own anything similar.").font(.caption).foregroundStyle(Theme.secondaryText)
            } else {
                headline("\(result.duplicates.count) similar item\(result.duplicates.count == 1 ? "" : "s")", good: false)
                let wears = result.duplicates.map(\.item.wearCount).reduce(0, +)
                Text("You already own \(result.duplicates.count) like it, worn \(wears)× in total.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                ForEach(showDuplicatesAll ? result.duplicates : Array(result.duplicates.prefix(3))) { d in
                    HStack(spacing: 10) {
                        ItemImage(item: d.item).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.item.name).font(.subheadline)
                            Text("\(d.level) · \(d.reasons.prefix(3).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int((d.score * 100).rounded()))%").font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(d.item.daysSinceWorn.map { $0 >= 30 ? "idle \($0)d" : "worn \(d.item.wearCount)×" } ?? "worn \(d.item.wearCount)×")
                                .font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                if result.duplicates.count > 3 {
                    Button(showDuplicatesAll ? "Show fewer" : "Show all \(result.duplicates.count)") { showDuplicatesAll.toggle() }
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.primary)
                }
            }
        }
    }

    private var styleCard: some View {
        Card(label: "YOUR STYLE") {
            HStack(alignment: .firstTextBaseline) {
                headline(result.styleFit.label, good: result.styleFit.score >= 55)
                Spacer()
                Text("\(result.styleFit.score)/100").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(result.styleFit.score >= 55 ? Theme.primary : Color(hex: 0xB5651D))
                        .frame(width: g.size.width * CGFloat(result.styleFit.score) / 100)
                }
            }
            .frame(height: 6)
            ForEach(result.styleFit.reasons, id: \.self) { r in
                Label(r.text, systemImage: r.positive ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption).foregroundStyle(r.positive ? Theme.ink : Theme.secondaryText)
                    .symbolRenderingMode(.hierarchical)
            }
            if result.styleFit.reasons.isEmpty {
                Text("Log a few outfits or fill in your style so we can say more.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let notes = gemini?.styleNotes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(Theme.ink)
            }
            NavigationLink { StyleProfileView() } label: {
                Text("Edit your style ›").font(.caption.weight(.medium)).foregroundStyle(Theme.primary)
            }
        }
    }

    private var compatibilityCard: some View {
        NavigationLink {
            CompatibleItemsView(product: result.product, compatible: result.compatible)
        } label: {
            Card(label: "COMPATIBILITY", filled: true, chevron: true) {
                headline("Matches \(result.compatible.count) item\(result.compatible.count == 1 ? "" : "s")", good: !result.compatible.isEmpty)
                Text(outfitLine).font(.caption).foregroundStyle(Theme.secondaryText)
                if !result.outfits.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(result.outfits.prefix(4)) { OutfitBoard(outfit: $0, size: 110) }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var outfitLine: String {
        let n = result.outfits.count
        guard n > 0 else { return "No complete outfits with what you own yet." }
        let base = "Makes \(n) outfit\(n == 1 ? "" : "s")"
        return result.duplicates.isEmpty ? base + ". Tap to see what it goes with." : base + " — \(result.newOutfitCount) you can't already make."
    }

    private var costCard: some View {
        Card(label: "COST PER WEAR") {
            headline(result.costPerWear.map { "≈ \($0.dollars)" } ?? "Add a price", good: true)
            Text("If you wear it about \(Int(result.predictedWearsPerYear.rounded())) times a year for 2 years — based on how often you wear similar \(result.product.category.filterTitle.lowercased()), adjusted for style fit and what you already own.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private func headline(_ text: String, good: Bool) -> some View {
        Text(text).font(.headline).foregroundStyle(good ? Theme.primary : Color(hex: 0xB5651D))
    }
}

private struct Card<Content: View>: View {
    let label: String
    var filled = false
    var chevron = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.caption2.weight(.medium)).foregroundStyle(Theme.secondaryText)
                content
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText) }
        }
        .padding(14)
        .background(filled ? Theme.mint : .clear, in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }
}

#Preview {
    NavigationStack {
        PurchaseResultView(result: ClosetStore.preview.check(SampleData.exampleProducts[0])) {}
    }
    .environment(ClosetStore.preview)
}
