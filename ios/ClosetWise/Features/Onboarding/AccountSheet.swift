import SwiftUI

/// Save this closet to an email, or sign in to one saved from another phone.
/// Both are two steps: enter the email, then the code Supabase emails to it.
struct AccountSheet: View {
    enum Mode { case save, signIn }

    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var onSignedIn: () -> Void = {}

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    private var validEmail: Bool {
        email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
    private var validCode: Bool { (6...10).contains(code.count) && code.allSatisfy(\.isNumber) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: mode == .save ? "lock.icloud" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34)).foregroundStyle(Theme.primary)
                Text(title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)

                if !codeSent {
                    TextField(text: $email, prompt: Text(verbatim: "you@example.com")) { Text("Email") }
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.send)
                        .onSubmit { if validEmail { Task { await sendCode() } } }
                        .padding(14)
                        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter the code sent to \(email)").font(.subheadline.weight(.medium))
                        TextField("6-digit code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .font(.title2.monospacedDigit())
                            .focused($focus, equals: .code)
                            .padding(14)
                            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
                            .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(10)) }
                        HStack {
                            Button("Use a different email") { codeSent = false; code = ""; error = nil; focus = .email }
                            Spacer()
                            Button("Send again") { Task { await sendCode() } }.disabled(working)
                        }
                        .font(.footnote)
                    }
                }

                if mode == .signIn, !store.items.isEmpty, !store.hasOnlyDemoItems {
                    Label("The \(store.items.count) pieces on this phone will be replaced by the closet saved to that email.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.red)
                }

                Spacer()

                PrimaryButton(title: working ? "One moment…" : codeSent ? confirmTitle : "Email me a code") {
                    Task { codeSent ? await confirm() : await sendCode() }
                }
                .disabled(working || (codeSent ? !validCode : !validEmail))
                .opacity(working || (codeSent ? !validCode : !validEmail) ? 0.5 : 1)
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focus = .email }
            .animation(.easeInOut(duration: 0.2), value: codeSent)
            .animation(.easeInOut(duration: 0.2), value: error)
        }
    }

    private var title: String { mode == .save ? "Save your closet" : "Sign in to your closet" }
    private var subtitle: String {
        mode == .save
            ? "Right now your closet lives with this app. Save it to your email so it's safe if you delete the app, and so you can open it on another phone."
            : "Use the email you saved your closet to. We'll email you a code — no password needed."
    }
    private var confirmTitle: String { mode == .save ? "Save my closet" : "Sign in" }

    private func sendCode() async {
        working = true
        error = nil
        defer { working = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            if mode == .save { try await Cloud.shared.sendSaveCode(to: address) } else { try await Cloud.shared.sendSignInCode(to: address) }
            email = address
            codeSent = true
            focus = .code
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func confirm() async {
        working = true
        error = nil
        defer { working = false }
        do {
            if mode == .save {
                try await Cloud.shared.confirmSaveCode(email: email, code: code, store: store)
            } else {
                try await Cloud.shared.confirmSignIn(email: email, code: code, store: store)
            }
            onSignedIn()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ClosetStore {
    /// True when everything in the closet came from the demo (nothing the user would lose).
    var hasOnlyDemoItems: Bool {
        let demo = Set(SampleData.wardrobe.map(\.id))
        return items.allSatisfy { demo.contains($0.id) }
    }
}
