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
            if phase == .background {
                // Make sure queued writes land before the process can be suspended.
                Task { await container.cart.flush() }
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
