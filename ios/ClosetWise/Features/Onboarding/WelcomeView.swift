import SwiftUI

/// First launch: name and a few vibes, then start empty or with a demo closet.
struct WelcomeView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var page = 0
    @State private var name = ""
    @State private var vibes: [String] = []
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                intro.tag(0)
                aboutYou.tag(1)
                start.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule().fill(i == page ? Theme.primary : Theme.border).frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.spring, value: page)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    // MARK: Pages

    private var intro: some View {
        VStack(spacing: 20) {
            Spacer()
            AppLogo(size: 150)
            VStack(spacing: 10) {
                Text("ClosetWise").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                Text("Check a piece against the closet you already own — before you buy it.")
                    .font(.title3).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            }
            Spacer()
            PrimaryButton(title: "Get started") { page = 1 }
        }
        .padding(28)
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer().frame(height: 20)
            Text("A little about you").font(.title.weight(.bold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?").font(.subheadline.weight(.medium))
                TextField("Your first name", text: $name)
                    .textContentType(.givenName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .padding(14)
                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Your vibe (optional)").font(.subheadline.weight(.medium))
                FlowLayout(spacing: 8) {
                    ForEach(StylePreferences.vibeOptions.prefix(12), id: \.self) { v in
                        Button { vibes.toggle(v) } label: { Chip(title: v, selected: vibes.contains(v)) }
                    }
                }
                Text("You can change this any time in Your style.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            PrimaryButton(title: "Continue") { nameFocused = false; page = 2 }
        }
        .padding(28)
        .onTapGesture { nameFocused = false }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(name.isEmpty ? "How do you want to start?" : "Nice to meet you, \(name.trimmingCharacters(in: .whitespaces)).")
                .font(.title.weight(.bold)).foregroundStyle(Theme.ink)
            Text("ClosetWise works best once it knows what's in your closet.")
                .foregroundStyle(Theme.secondaryText)
            choice(icon: "camera", title: "Add my clothes", subtitle: "Snap a few favourites — ClosetWise fills in the details.") {
                finish(demo: false)
                router.tab = .add
            }
            choice(icon: "sparkles", title: "Try a demo closet", subtitle: "16 sample pieces and a few weeks of outfits. Clear it any time.") {
                finish(demo: true)
                router.tab = .home
            }
            Spacer()
        }
        .padding(28)
    }

    private func choice(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.primary)
                    .frame(width: 48, height: 48).background(Theme.mint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
        }
        .buttonStyle(.plain)
    }

    private func finish(demo: Bool) {
        store.profile = UserProfile(name: name.trimmingCharacters(in: .whitespaces), onboarded: true)
        for v in vibes where !store.preferences.vibes.contains(v) { store.preferences.vibes.append(v) }
        if demo { store.loadDemo(account: Cloud.shared.accountID) } else { store.save() }
    }
}

/// Name, account, Gemini key, demo closet.
struct SettingsSheet: View {
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var confirmSignOut = false
    @State private var confirmRemoveDemo = false
    private var cloud: Cloud { Cloud.shared }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $store.profile.name)
                        .onSubmit { store.save() }
                    NavigationLink("Your style") { StyleProfileView() }
                }
                accountSection
                Section {
                    NavigationLink { GeminiKeyView() } label: {
                        LabeledContent("Gemini API key", value: GeminiKey.shared.hint ?? "Not set")
                    }
                } header: { Text("AI") } footer: {
                    Text("ClosetWise's AI reads use your own free Gemini key.")
                }
                Section {
                    if store.hasDemoData {
                        Button("Remove the demo closet", role: .destructive) { confirmRemoveDemo = true }
                    } else {
                        Button("Load the demo closet") { store.loadDemo(account: Cloud.shared.accountID); dismiss() }
                    }
                    Button("Clear my closet", role: .destructive) { confirmClear = true }
                } header: { Text("Closet") } footer: {
                    Text("Clearing removes your items, outfits and checks here and on any other phone signed in to this closet.")
                }
                Section {
                    HStack(spacing: 12) {
                        AppLogo(size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ClosetWise").font(.subheadline.weight(.semibold))
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.save(); dismiss() } } }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await cloud.signOut(store: store); dismiss() } }
            } message: {
                Text("Your closet stays saved to \(cloud.email ?? "your account"). This phone is cleared until you sign in again.")
            }
            .confirmationDialog("Remove the demo closet?", isPresented: $confirmRemoveDemo, titleVisibility: .visible) {
                Button("Remove demo pieces", role: .destructive) { store.removeDemo(); dismiss() }
            } message: {
                Text("Removes the sample pieces, outfits and checks. Everything you added yourself stays.")
            }
            .confirmationDialog("Clear your closet?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear closet", role: .destructive) { store.clearCloset(); dismiss() }
            } message: {
                Text("This removes \(store.items.count) items, \(store.logs.count) outfits and \(store.purchases.count) checks.")
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        Section("Account") {
            if !SupabaseService.isConfigured {
                Text("Supabase isn't configured, so your closet is saved on this phone only.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if let email = cloud.email { LabeledContent("Signed in as", value: email) }
                syncLine
                if cloud.isSignedIn {
                    NavigationLink("Set a password") { SetPasswordView() }
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }
        }
    }

    private var syncLine: some View {
        HStack {
            Text(cloud.lastError == nil ? cloud.status.message : "Couldn't sync — \(cloud.lastError ?? "")")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if cloud.syncing {
                ProgressView().controlSize(.small)
            } else if cloud.isSignedIn {
                Button("Sync now") { Task { await cloud.sync(store, pull: true) } }.font(.caption)
            }
        }
    }
}

/// Settings → Account → Set a password. Works while signed in, without any email.
struct SetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var done = false

    var body: some View {
        Form {
            Section {
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(working ? "Saving…" : "Save password") { Task { await save() } }
                    .disabled(working || password.count < AuthView.minPassword)
            } footer: {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                } else if done {
                    Label("Password saved. Use it with \(Cloud.shared.email ?? "your email") to sign in on any phone.", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.primary)
                } else {
                    Text("At least \(AuthView.minPassword) characters. You'll use it with \(Cloud.shared.email ?? "your email") to sign in on another phone.")
                }
            }
        }
        .navigationTitle("Set a password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await Cloud.shared.setPassword(password)
            password = ""
            done = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
