import SwiftUI

/// A clothing rail: pieces hang side-on, tapping one turns it to face you (and
/// nudges its neighbours), tapping it again lifts it off the rail.
struct ClothingRail: View {
    let items: [WardrobeItem]
    @Binding var selected: UUID?
    var height: CGFloat = 250
    var onOpen: (WardrobeItem) -> Void

    @State private var kicks: [UUID: SwingKick] = [:]
    @State private var brushed = false
    @State private var viewWidth: CGFloat = 0

    static let headroom: CGFloat = 10
    private var scale: CGFloat { height / 310 }
    /// Lowest hem on the rail, so the layout doesn't reserve space below the longest piece.
    private var visibleHem: CGFloat { (items.map(\.kind.hem).max() ?? 310) + 14 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        RailSlot(item: item, isFront: selected == item.id, height: height, visibleHem: visibleHem, kick: kicks[item.id] ?? SwingKick())
                            .id(item.id)
                            .onTapGesture { tap(index: index, proxy: proxy) }
                            .accessibilityElement()
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(selected == item.id ? "Opens details" : "Turns it to the front")
                    }
                }
                .padding(.horizontal, 36)
                // A short closet still gets a full-width rail, with its pieces centred.
                .frame(minWidth: viewWidth)
                .background(alignment: .top) {
                    RailBar(radius: max(3, 4.6 * scale))
                        .padding(.top, (Self.headroom - 1.5) * scale - max(3, 4.6 * scale))
                }
                .padding(.bottom, 12)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        .onAppear(perform: brush)
    }

    private func tap(index: Int, proxy: ScrollViewProxy) {
        let item = items[index]
        if selected == item.id { onOpen(item); return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            selected = item.id
            proxy.scrollTo(item.id, anchor: .center)
        }
        if index > 0 { kicks[items[index - 1].id, default: SwingKick()].next(-1) }
        if index + 1 < items.count { kicks[items[index + 1].id, default: SwingKick()].next(1) }
    }

    /// A light brush along the rail when it first appears.
    private func brush() {
        guard !brushed else { return }
        brushed = true
        for (i, item) in items.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.06) {
                kicks[item.id, default: SwingKick()].next(1, strength: max(0.4, 1 - Double(i) * 0.06))
            }
        }
    }
}

struct SwingKick: Equatable {
    var count = 0
    var direction: Double = 1
    var strength: Double = 1
    mutating func next(_ direction: Double, strength: Double = 1) {
        count += 1
        self.direction = direction
        self.strength = strength
    }
}

private struct RailSlot: View {
    let item: WardrobeItem
    let isFront: Bool
    let height: CGFloat
    let visibleHem: CGFloat
    let kick: SwingKick

    private var width: CGFloat { height * 200 / 310 }
    private var scale: CGFloat { height / 310 }
    private var slotWidth: CGFloat { (isFront ? 0.94 : item.kind.sideWidth) * width + height * 0.035 }
    private var hookAnchor: UnitPoint { UnitPoint(x: 0.5, y: ClothingRail.headroom / (310 + ClothingRail.headroom)) }

    var body: some View {
        ZStack(alignment: .top) {
            GarmentCanvas(kind: item.kind, face: .side, color: item.swatch, hanger: .wood, headroom: ClothingRail.headroom)
                .rotation3DEffect(.degrees(isFront ? -84 : 0), axis: (0, 1, 0), perspective: 0.5)
                .opacity(isFront ? 0 : 1)
            GarmentCanvas(kind: item.kind, face: .front, color: item.swatch, hanger: .wood, headroom: ClothingRail.headroom)
                .rotation3DEffect(.degrees(isFront ? 0 : -70), axis: (0, 1, 0), perspective: 0.5)
                .brightness(isFront ? 0 : -0.12)
                .opacity(isFront ? 1 : 0)
            if isFront, let price = item.price {
                PriceTag(text: price.dollars)
                    .padding(.top, (ClothingRail.headroom + 34) * scale)
                    .offset(x: 6)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: (310 + ClothingRail.headroom) * scale)
        .shadow(color: .black.opacity(0.16), radius: 6, x: 3, y: 8)
        .keyframeAnimator(initialValue: 0.0, trigger: kick) { content, angle in
            content.rotationEffect(.degrees(angle), anchor: hookAnchor)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(kick.direction * 9 * kick.strength, duration: 0.16)
                SpringKeyframe(-kick.direction * 4.5 * kick.strength, duration: 0.34)
                SpringKeyframe(kick.direction * 1.8 * kick.strength, duration: 0.34)
                SpringKeyframe(0, duration: 0.5)
            }
        }
        .frame(width: slotWidth, height: (visibleHem + ClothingRail.headroom) * scale, alignment: .top)
        .zIndex(isFront ? 1 : 0)
        .contentShape(Rectangle())
    }
}

private struct PriceTag: View {
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.ink.opacity(0.35)).frame(width: 1, height: 14)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6).padding(.top, 7).padding(.bottom, 4)
                .background(.white, in: RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .top) { Circle().fill(Theme.ink.opacity(0.3)).frame(width: 3, height: 3).padding(.top, 2) }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.ink.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        }
        .rotationEffect(.degrees(-12), anchor: .top)
    }
}

/// Brushed-metal rail with wall brackets.
private struct RailBar: View {
    let radius: CGFloat
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.78), location: 0), .init(color: .white, location: 0.18),
                    .init(color: Color(white: 0.72), location: 0.38), .init(color: Color(white: 0.55), location: 0.62),
                    .init(color: Color(white: 0.32), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 4)
            HStack {
                bracket
                Spacer()
                bracket
            }
            .padding(.horizontal, 6)
        }
        .frame(height: radius * 2)
    }

    private var bracket: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.55), Color(white: 0.4)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 14, height: 26)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 3)
    }
}
