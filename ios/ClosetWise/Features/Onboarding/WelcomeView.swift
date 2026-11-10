import SwiftUI

/// First launch: name and a few vibes, then start empty or with a demo closet.
struct WelcomeView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var page = 0
    @State private var name = ""
    @State private var vibes: [String] = []
    @FocusState private var nameFocused: Bool
    @State private var showSignIn = false

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
            GarmentCanvas(kind: .knit, face: .front, color: Theme.primary, hanger: .wood, headroom: 10)
                .frame(width: 150, height: 220)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 10)
            VStack(spacing: 10) {
                Text("ClosetWise").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                Text("Check a piece against the closet you already own — before you buy it.")
                    .font(.title3).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            }
            Spacer()
            PrimaryButton(title: "Get started") { page = 1 }
            Button("I already have a closet saved") { showSignIn = true }
                .font(.subheadline.weight(.medium))
        }
        .padding(28)
        .sheet(isPresented: $showSignIn) {
            AccountSheet(mode: .signIn) { router.tab = .home }
        }
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
        if demo { store.loadDemo() } else { store.save() }
    }
}

extension AccountSheet.Mode: Identifiable {
    public var id: Self { self }
}

/// Name, account, demo closet.
struct SettingsSheet: View {
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var account: AccountSheet.Mode?
    @State private var confirmSignOut = false
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
                    if store.hasDemoItems {
                        Text("You're using the demo closet.").foregroundStyle(.secondary)
                    } else {
                        Button("Load the demo closet") { store.loadDemo(); dismiss() }
                    }
                    Button("Clear my closet", role: .destructive) { confirmClear = true }
                } header: { Text("Closet") } footer: {
                    Text("Clearing removes your items, outfits and checks here and on any other phone signed in to this closet.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.save(); dismiss() } } }
            .sheet(item: $account) { mode in AccountSheet(mode: mode) }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await cloud.signOut(store: store); dismiss() } }
            } message: {
                Text("Your closet stays saved to \(cloud.email ?? "your email"). This phone starts fresh until you sign in again.")
            }
            .confirmationDialog("Clear your closet?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear closet", role: .destructive) { store.clearCloset(); dismiss() }
            } message: {
                Text("This removes \(store.items.count) items, \(store.logs.count) outfits and \(store.purchases.count) checks.")
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        Section {
            if let email = cloud.email {
                LabeledContent("Saved to", value: email)
                syncLine
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } else {
                Button { account = .save } label: {
                    Label("Save my closet to an email", systemImage: "lock.icloud")
                }
                .disabled(!cloud.isSignedIn)
                Button { account = .signIn } label: {
                    Label("I already have a closet saved", systemImage: "person.crop.circle")
                }
                .disabled(!cloud.isSignedIn)
                syncLine
            }
        } header: { Text("Account") } footer: {
            if cloud.email == nil, cloud.isSignedIn {
                Text("Until you save it, your closet is tied to this app — deleting the app loses it.")
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
