import Data
import Domain
import Foundation
import Networking
import NovaCore
import Routing

/// Composition root. The only place that knows concrete types; everything else sees protocols.
///
/// Two backends, one app: **fixtures** (bundled JSON, no account needed — what a reviewer gets by
/// default, and what UI tests use) or **Supabase** (enabled by the git-ignored
/// `Config/Supabase.local.xcconfig`). Features can't tell the difference.
///
/// Launch-time discipline: `init` only allocates small objects — no disk, no network, no Keychain.
/// All I/O (session restore, local-first hydration, first sync) happens in `bootstrap()`, which runs
/// *after* the first frame is on screen.
@MainActor
public final class AppContainer {
    public let configuration: AppConfiguration

    // Services (ports → adapters)
    public let catalog: any CatalogRepository
    public let auth: any AuthService
    public let orders: any OrderService
    public let profile: any ProfileRepository
    public let notifications: any NotificationRepository

    // Shared observable state
    public let network: NetworkMonitor
    public let router: Router
    public let session: SessionStore
    public let cart: CartStore
    public let wishlist: WishlistStore
    public let recentlyViewed: RecentlyViewedStore
    public let searchHistory: SearchHistoryStore
    public let sync: SyncCoordinator

    private let vault: SessionVault?
    private var didBootstrap = false

    public var isBackendEnabled: Bool {
        configuration.environment == .supabase
    }

    public var backendDescription: String {
        isBackendEnabled ? "Supabase · \(configuration.apiBaseURL.host() ?? "")" : "Offline demo data"
    }

    public init(configuration: AppConfiguration) {
        self.configuration = configuration
        let inMemory = configuration.isUITesting
        let latency = configuration.simulatedLatency
        network = NetworkMonitor(monitoring: !inMemory)

        func store<Value: Codable & Sendable>(_ name: String, _: Value.Type) -> any Persisting<Value> {
            inMemory ? InMemoryStore<Value>() : FileStore<Value>(filename: name)
        }

        let cartRepository: any LocalFirstRepository<CartItem>
        let wishlistRepository: any LocalFirstRepository<Product>
        let coupons: any CouponService

        switch configuration.environment {
        case .fixtures:
            let transport = GatedTransport(FixtureTransport(latency: latency), gate: network.gate)
            let client = APIClient(baseURL: configuration.apiBaseURL, transport: transport)
            vault = nil
            catalog = RemoteCatalogRepository(source: FixtureCatalogSource(client: client))
            notifications = RemoteNotificationRepository(client: client)
            auth = LocalAuthService(
                secureStorage: inMemory ? EphemeralSecureStorage() : KeychainStore(),
                inMemory: inMemory,
                latency: latency
            )
            orders = LocalOrderService(store: store("orders", [Order].self), processingTime: inMemory ? .milliseconds(300) : .seconds(2))
            profile = LocalProfileRepository(
                addressStore: store("addresses", [Address].self),
                paymentStore: store("payment-methods", [PaymentMethod].self)
            )
            coupons = LocalCouponService(latency: latency)
            cartRepository = SyncedCollection(remote: LocalOnlyRemote<CartItem>(), filename: "cart-v2", inMemory: inMemory)
            wishlistRepository = SyncedCollection(
                remote: LocalOnlyRemote<Product>(), filename: "wishlist-v2", inMemory: inMemory, newestFirst: true
            )

        case .supabase:
            let supabase = SupabaseConfig(url: configuration.apiBaseURL, publishableKey: configuration.supabasePublishableKey)
            let transport = GatedTransport(URLSessionTransport(), gate: network.gate)
            let vault = SessionVault(config: supabase, storage: KeychainStore(service: "com.novashop.app.supabase"), transport: transport)
            let api = APIClient(
                baseURL: supabase.url,
                transport: transport,
                authorizer: SupabaseAuthorizer(vault: vault, publishableKey: supabase.publishableKey)
            )
            let userID: CurrentUserID = { await vault.current()?.user.id }
            self.vault = vault
            catalog = RemoteCatalogRepository(
                source: SupabaseCatalogSource(client: api),
                diskCache: FileStore<CatalogSnapshot>(filename: "catalog-cache")
            )
            notifications = SupabaseNotificationRepository(client: api)
            auth = SupabaseAuthService(config: supabase, vault: vault, transport: transport, api: api)
            orders = SupabaseOrderService(client: api)
            profile = SupabaseProfileRepository(client: api, userID: userID)
            coupons = SupabaseCouponService(client: api)
            cartRepository = SyncedCollection(remote: SupabaseCartRemote(client: api, userID: userID), filename: "cart-v2")
            wishlistRepository = SyncedCollection(
                remote: SupabaseWishlistRemote(client: api, userID: userID), filename: "wishlist-v2", newestFirst: true
            )
        }

        router = Router()
        session = SessionStore(auth: auth)
        cart = CartStore(repository: cartRepository, couponService: coupons)
        wishlist = WishlistStore(repository: wishlistRepository)
        recentlyViewed = RecentlyViewedStore(persistence: store("recently-viewed", [Product].self))
        searchHistory = SearchHistoryStore(persistence: store("search-history", [String].self))
        sync = SyncCoordinator(
            network: network, session: session, cart: cart, wishlist: wishlist,
            isBackendEnabled: configuration.environment == .supabase
        )

        router.isAuthenticated = { [unowned session] in session.isSignedIn }
    }

    public static func live() -> AppContainer {
        AppContainer(configuration: .current)
    }

    /// Post-first-frame work. Independent hydrations run concurrently.
    public func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        network.start()

        await Perf.measure("Launch.Bootstrap") {
            async let restore: Void = session.restore()
            async let cartLoad: Void = cart.hydrate()
            async let wishlistLoad: Void = wishlist.hydrate()
            async let recentsLoad: Void = recentlyViewed.hydrate()
            async let historyLoad: Void = searchHistory.hydrate()
            _ = await (restore, cartLoad, wishlistLoad, recentsLoad, historyLoad)
        }

        sync.start()
        if let vault {
            let session = session
            Task {
                for await _ in vault.expirations {
                    session.handleSessionExpired()
                }
            }
        }

        if configuration.startSignedIn, configuration.environment == .fixtures, !session.isSignedIn {
            try? await session.signIn(email: "olivia.chen@novashop.example", password: "password123")
            _ = try? await profile.save(Address(
                fullName: "Olivia Chen", line1: "123 Maple Street", city: "San Francisco", state: "CA", postalCode: "94110", isDefault: true
            ))
        }
        await sync.syncAll(reason: "launch")
    }

    public func didBecomeActive() async {
        await sync.syncAll(reason: "foreground")
    }

    public func backgroundSync() async {
        await sync.syncAll(reason: "background refresh")
    }

    public var hasPendingChanges: Bool {
        !cart.pendingItemIDs.isEmpty || !wishlist.list.pendingIDs.isEmpty
    }
}
