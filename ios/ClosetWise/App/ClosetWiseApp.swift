import SwiftUI

@main
struct ClosetWiseApp: App {
    @State private var store = ClosetStore.load()
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FrameHitchMonitor.startIfRequested()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-checkLink") { _router = State(initialValue: { let r = AppRouter(); r.tab = .check; return r }()) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Theme.primary)
                .environment(store)
                .environment(router)
                .task { await Cloud.shared.start(store) }
                .task { await WeatherService.shared.attach(store) }
                .onChange(of: scenePhase) { old, new in
                    // Coming back to the app: pick up changes made on another phone.
                    if new == .active, old == .background {
                        Task { await Cloud.shared.refresh(store) }
                        Task { await WeatherService.shared.attach(store) }
                    }
                }
        }
    }
}

struct RootTabView: View {
    @Environment(ClosetStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppRouter.Tab.home)
            NavigationStack { ClosetView() }
                .tabItem { Label("Closet", systemImage: "hanger") }
                .tag(AppRouter.Tab.closet)
            NavigationStack { AddItemView() }
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(AppRouter.Tab.add)
            NavigationStack { CheckPurchaseView() }
                .tabItem { Label("Check", systemImage: "checkmark.circle") }
                .tag(AppRouter.Tab.check)
        }
        .fullScreenCover(isPresented: .constant(!store.profile.onboarded)) {
            WelcomeView()
        }
    }
}

#Preview {
    RootTabView().tint(Theme.primary).environment(ClosetStore.preview).environment(AppRouter())
}
