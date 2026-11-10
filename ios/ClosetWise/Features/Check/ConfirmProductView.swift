import SwiftUI

/// The item form, used to confirm a product before a purchase check, to add a piece to
/// the closet, or to edit one. Type, colour and fit drive everything downstream.
struct ConfirmProductView: View {
    enum Mode { case purchase, addToCloset, edit }

    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: ConfirmRequest
    var mode: Mode = .purchase
    let onFinish: () -> Void
    @State private var confirmRemove = false

    @State private var item: WardrobeItem
    @State private var priceText: String
    @State private var result: PurchaseCheckResult?

    init(request: ConfirmRequest, mode: Mode = .purchase, onFinish: @escaping () -> Void) {
        self.request = request
        self.mode = mode
        self.onFinish = onFinish
        _item = State(initialValue: request.item)
        _priceText = State(initialValue: request.item.price.map { "\($0)" } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ItemImage(item: item).frame(height: 190)

                if mode != .edit {
                    Label(request.source.note, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }

                field("Name") {
                    TextField("e.g. Black ribbed top", text: $item.name).textFieldStyle(.roundedBorder)
                }

                field("Type") {
                    Menu {
                        Picker("Type", selection: Binding(get: { item.kind }, set: { setKind($0) })) {
                            ForEach(GarmentKind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    } label: {
                        HStack {
                            Text(item.kind.label).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    }
                }

                field("Colour", trailing: item.color.capitalized) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(StylePreferences.palette, id: \.name) { c in
                                let on = item.color == c.name
                                Button {
                                    item.color = c.name
                                    item.hex = c.hex
                                } label: {
                                    Circle().fill(Color(hex: c.hex))
                                        .overlay(Circle().stroke(Theme.border))
                                        .overlay(Circle().stroke(Theme.primary, lineWidth: on ? 2.5 : 0).padding(-3))
                                        .frame(width: 30, height: 30)
                                        .padding(3)
                                }
                                .accessibilityLabel("\(c.name)\(on ? ", selected" : "")")
                            }
                        }
                    }
                }

                field("Fit", trailing: item.fit.blurb) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FitType.allCases) { fit in
                                Button { item.fit = fit } label: { Chip(title: fit.label, selected: item.fit == fit) }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    field("Cut") {
                        TextField("wide-leg, cropped…", text: Binding(get: { item.silhouette ?? "" }, set: { item.silhouette = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    }
                    field("Fabric") {
                        TextField("cotton, wool…", text: $item.material).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    }
                }

                field("How dressy", trailing: StylePreferences.dressinessLabels[item.formality - 1]) {
                    Picker("How dressy", selection: $item.formality) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    field("Price") {
                        TextField("$", text: $priceText).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                    }
                    field("Store") {
                        TextField("optional", text: Binding(get: { item.store ?? "" }, set: { item.store = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
                    }
                }


                if mode == .edit {
                    Button("Remove from closet", role: .destructive) { confirmRemove = true }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.pad)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: primaryTitle, systemImage: mode == .purchase ? "checkmark.circle" : nil, action: submit)
                .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .navigationTitle(mode == .edit ? "Edit item" : mode == .addToCloset ? "Add to closet" : "Confirm the item")
        .confirmationDialog("Remove \(item.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.removeItem(request.item); onFinish() }
        } message: {
            Text("It leaves your closet and suggestions. Past outfits that used it stay in your history.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $result) { r in
            PurchaseResultView(result: r, onFinish: onFinish)
        }
    }

    private func submit() {
        item.price = Decimal(string: priceText.replacingOccurrences(of: "$", with: ""))
        item.style = item.style.isEmpty ? "casual" : item.style
        item.name = item.name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .purchase:
            result = store.check(item)
        case .addToCloset, .edit:
            store.updateItem(item)
            onFinish()
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .purchase: "Check against my closet"
        case .addToCloset: "Save to closet"
        case .edit: "Save changes"
        }
    }

    private func setKind(_ kind: GarmentKind) {
        item.kind = kind
        item.category = AttributeGuesser.category(for: kind)
    }

    private func field<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(Theme.secondaryText) }
            }
            content()
        }
    }
}

extension GarmentKind {
    var label: String {
        switch self {
        case .tee: "T-shirt / tank"
        case .knit: "Knit / sweater / long sleeve"
        case .hoodie: "Hoodie / sweatshirt"
        case .shirt: "Shirt / blouse"
        case .jacket: "Jacket / blazer"
        case .coat: "Coat"
        case .trousers: "Jeans / trousers"
        case .skirt: "Skirt"
        case .shorts: "Shorts"
        case .shoes: "Shoes"
        }
    }
}
