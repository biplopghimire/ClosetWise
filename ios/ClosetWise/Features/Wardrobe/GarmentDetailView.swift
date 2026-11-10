import SwiftUI

/// A piece lifted off the rail: drag (or tap Front / Back) to turn it around.
struct GarmentDetailView: View {
    let item: WardrobeItem
    let index: Int
    let total: Int
    let outfits: [Outfit]

    @State private var angle: Double = 0
    @State private var dragStart: Double?
    @State private var editing = false
    /// Pieces added from a photo open on the photo; the drawing is one tap away.
    @State private var showPhoto = true
    @Environment(\.dismiss) private var dismiss

    private var showingBack: Bool { cos(angle * .pi / 180) < 0 }
    private var photo: UIImage? { item.photo.flatMap(ClosetStore.photo) }
    private var showingPhoto: Bool { showPhoto && photo != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil").font(.subheadline.weight(.medium)) }
                }
                if showingPhoto, let photo { photoStage(photo) } else { stage }

                if photo != nil {
                    Picker("View", selection: $showPhoto.animation(.easeInOut(duration: 0.25))) {
                        Text("Photo").tag(true)
                        Text("Illustration").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity)
                }

                if item.kind.hangs && !showingPhoto {
                    HStack(spacing: 24) {
                        faceButton("Front", back: false)
                        faceButton("Back", back: true)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%02d / %02d", index + 1, total))
                        .font(.caption.monospaced()).foregroundStyle(Theme.secondaryText)
                    Text(item.name).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    FlowChips(values: ([item.color, item.material, item.fit.label] + [item.silhouette, item.style].compactMap { $0 }).map(\.capitalized))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    StatCard(value: "\(item.wearCount)×", label: "worn")
                    StatCard(value: item.costPerWear?.dollars ?? "—", label: "per wear", accent: true)
                    StatCard(value: item.daysSinceWorn.map { "\($0)d" } ?? "—", label: "since last worn")
                }

                if !outfits.isEmpty {
                    SectionHeader(title: "Outfits with this", trailing: "From your closet")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(outfits) { OutfitCard(outfit: $0, size: 150) }
                        }
                    }
                }
            }
            .padding(Theme.pad)
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ConfirmProductView(request: ConfirmRequest(item: item, source: .manual), mode: .edit) {
                    editing = false
                    dismiss()
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } } }
            }
        }
    }

    /// The real photo of the piece (background removed when the phone could do it).
    private func photoStage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .blendMode(.multiply)
            .padding(24)
            .frame(height: 354)
            .frame(maxWidth: .infinity)
            .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.corner))
            .accessibilityLabel("Photo of \(item.name)")
            .transition(.opacity)
    }

    private var stage: some View {
        let height: CGFloat = 330
        return ZStack(alignment: .top) {
            if item.kind.hangs {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.55), Color(white: 0.4)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 3, height: 30)
                    .offset(y: -24)
            }
            ZStack(alignment: .top) {
                face(back: false)
                    .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), perspective: 0.45)
                    .opacity(showingBack ? 0 : 1)
                face(back: true)
                    .rotation3DEffect(.degrees(angle + 180), axis: (0, 1, 0), perspective: 0.45)
                    .opacity(showingBack ? 1 : 0)
            }
            .frame(height: height)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 4, y: 12)
            .contentShape(Rectangle())
            .gesture(item.kind.hangs ? turnGesture : nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .background(Theme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func face(back: Bool) -> some View {
        GarmentCanvas(kind: item.kind, face: back ? .back : .front, color: item.swatch,
                      hanger: item.kind.hangs ? .wood : .none, headroom: item.kind.hangs ? 10 : 0)
            .padding(item.kind.hangs ? 0 : 40)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? angle
                dragStart = start
                angle = start + value.translation.width * 0.45
            }
            .onEnded { _ in
                dragStart = nil
                snap(to: showingBack)
            }
    }

    private func snap(to back: Bool) {
        let base = (angle / 360).rounded() * 360
        var target = base + (back ? 180 : 0)
        if target - angle > 180 { target -= 360 } else if angle - target > 180 { target += 360 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { angle = target }
    }

    private func faceButton(_ title: String, back: Bool) -> some View {
        let active = showingBack == back
        return Button { snap(to: back) } label: {
            VStack(spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(active ? Theme.ink : Theme.secondaryText)
                Rectangle().fill(active ? Theme.ink : .clear).frame(height: 1)
            }
            .fixedSize()
        }
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Wrapping row of pill chips.
struct FlowChips: View {
    let values: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(values, id: \.self) { Chip(title: $0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(in: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in zip(subviews, rows(in: bounds.width, subviews).points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func rows(in width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
