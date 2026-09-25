import AccountFeature
import AuthFeature
import DesignSystem
import Domain
import NovaCore
import Routing
import SwiftUI

/// App shell: five tabs, one `NavigationStack` per tab (each keeps its own history, like every
/// first-party app), a single route → view mapping, and the auth sheet.
public struct RootView: View {
    private let container: AppContainer
    @Bindable private var router: Router
    @AppStorage("settings.appearance") private var appearance: AppearancePreference = .system
    @Environment(\.scenePhase) private var scenePhase

    public init(container: AppContainer) {
        self.container = container
        router = container.router
        NovaAppearance.configure()
    }

    public var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.select($0) })) {
            tab(.home, title: "Home", icon: "house") { container.makeHome() }
            tab(.shop, title: "Shop", icon: "square.grid.2x2") { container.makeShop() }
            tab(.search, title: "Search", icon: "magnifyingglass") { container.makeSearch() }
            tab(.wishlist, title: "Wishlist", icon: "heart") { container.makeWishlist() }
                .badge(container.wishlist.count)
            tab(.account, title: "Account", icon: "person") { container.makeAccount() }
        }
        .tint(NovaColor.accent)
        .preferredColorScheme(appearance.colorScheme)
        .environment(container.router)
        .environment(container.session)
        .environment(container.cart)
        .environment(container.wishlist)
        .environment(container.recentlyViewed)
        .environment(container.network)
        .overlay(alignment: .top) {
            ConnectivityBanner(network: container.network, cart: container.cart)
        }
        .alert("Session expired", isPresented: Binding(
            get: { container.session.expiredNotice },
            set: {
                if !$0 {
                    container.session.dismissExpiredNotice()
                }
            }
        )) {
            Button("Sign In") { router.present(.auth(then: nil)) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("For your security you've been signed out. Your bag is saved on this device.")
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .auth:
                AuthFlowView { container.router.completeAuthentication() }
                    .environment(container.session)
            }
        }
        .onOpenURL { url in
            if let link = DeepLink(url: url) {
                router.handle(link)
            }
        }
        .onAppear { LaunchTimeline.shared.markFirstFrame() }
        .task {
            await container.bootstrap()
            DeferredLaunchWork.schedule()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await container.didBecomeActive() }
            case .background:
                // Land queued writes before suspension; if anything still needs uploading, ask iOS
                // for a background refresh window to sync it.
                Task {
                    await container.cart.flush()
                    await container.wishlist.flush()
                    if container.hasPendingChanges, container.isBackendEnabled {
                        BackgroundSync.schedule()
                    }
                }
            default:
                break
            }
        }
    }

    private func tab(_ tab: AppTab, title: String, icon: String, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            root()
                .navigationDestination(for: Route.self) { route in
                    container.destination(for: route)
                }
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(tab)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}
