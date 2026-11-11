import SwiftUI

/// The first screen when Supabase is set up: create an account, sign in, or reset a password.
/// Accounts are email + password. "Forgot password?" emails a one-time code, then sets a new one
/// (also how accounts from the old email-code sign-in get a password).
struct AuthView: View {
    enum Mode { case signUp, signIn, reset }

    @Environment(ClosetStore.self) private var store
    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }
    static let minPassword = 8

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }
    private var validEmail: Bool {
        cleanEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
    private var validPassword: Bool { password.count >= Self.minPassword }
    private var validCode: Bool { (6...10).contains(code.count) && code.allSatisfy(\.isNumber) }

    private var canSubmit: Bool {
        switch mode {
        case .signUp, .signIn: validEmail && (mode == .signIn ? !password.isEmpty : validPassword)
        case .reset: codeSent ? validCode && validPassword : validEmail
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 10) {
                    AppLogo(size: mode == .signIn ? 120 : 76)
                        .padding(.bottom, 6)
                    Text(title).font(.title.weight(.bold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 8)

                if mode == .reset && codeSent {
                    codeField
                    passwordField(prompt: "New password")
                } else {
                    emailField
                    if mode != .reset { passwordField(prompt: "Password") }
                }

                if mode == .signUp {
                    Text("At least \(Self.minPassword) characters.").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                if mode == .signIn {
                    Button("Forgot password?") { switchTo(.reset) }.font(.footnote.weight(.medium))
                }
                if mode != .signUp, !store.items.isEmpty, !store.hasOnlyDemoItems {
                    Label("The \(store.items.count) pieces on this phone will be replaced by that account's closet.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
                }

                PrimaryButton(title: working ? "One moment…" : buttonTitle) { Task { await submit() } }
                    .disabled(working || !canSubmit)
                    .opacity(working || !canSubmit ? 0.5 : 1)
                    .padding(.top, 6)

                HStack {
                    Spacer()
                    switch mode {
                    case .signUp: Button("I already have an account") { switchTo(.signIn) }
                    case .signIn: Button("Create an account") { switchTo(.signUp) }
                    case .reset: Button("Back to sign in") { switchTo(.signIn) }
                    }
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        .animation(.easeInOut(duration: 0.2), value: mode)
        .animation(.easeInOut(duration: 0.2), value: codeSent)
        .animation(.easeInOut(duration: 0.2), value: error)
    }

    // MARK: Fields

    private var emailField: some View {
        TextField(text: $email, prompt: Text(verbatim: "you@example.com")) { Text("Email") }
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = mode == .reset ? nil : .password }
            .padding(14)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
    }

    private func passwordField(prompt: String) -> some View {
        HStack {
            Group {
                if showPassword { TextField(prompt, text: $password) } else { SecureField(prompt, text: $password) }
            }
            .textContentType(mode == .signIn ? .password : .newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { if canSubmit { Task { await submit() } } }
            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.secondaryText)
            }
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
        }
        .padding(14)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter the code sent to \(cleanEmail)").font(.subheadline.weight(.medium))
            TextField("Code from the email", text: $code)
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

    // MARK: Text

    private var title: String {
        switch mode {
        case .signUp: "Create your account"
        case .signIn: "Welcome back"
        case .reset: "Reset your password"
        }
    }

    private var subtitle: String {
        switch mode {
        case .signUp: "Keep your closet safe and open it on any phone."
        case .signIn: "Sign in to open your closet."
        case .reset: codeSent ? "Type the code from the email, then choose a new password." : "We'll email you a code to set a new password."
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .signUp: "Create account"
        case .signIn: "Sign in"
        case .reset: codeSent ? "Set new password" : "Email me a code"
        }
    }

    // MARK: Actions

    private func switchTo(_ new: Mode) {
        mode = new
        error = nil
        code = ""
        codeSent = false
        password = ""
        focus = validEmail ? (new == .reset ? nil : .password) : .email
    }

    private func submit() async {
        guard canSubmit, !working else { return }
        if mode == .reset && !codeSent { await sendCode(); return }
        working = true
        error = nil
        defer { working = false }
        do {
            switch mode {
            case .signUp: try await Cloud.shared.signUp(email: cleanEmail, password: password, store: store)
            case .signIn: try await Cloud.shared.signIn(email: cleanEmail, password: password, store: store)
            case .reset: try await Cloud.shared.resetPassword(email: cleanEmail, code: code, newPassword: password, store: store)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendCode() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await Cloud.shared.sendResetCode(to: cleanEmail)
            email = cleanEmail
            password = ""
            codeSent = true
            focus = .code
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ClosetStore {
    /// True when everything in the closet came from the demo (nothing the user would lose).
    var hasOnlyDemoItems: Bool {
        items.allSatisfy { SampleData.isDemoItem($0.id) }
    }
}
