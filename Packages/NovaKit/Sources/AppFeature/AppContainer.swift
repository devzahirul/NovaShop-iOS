import Data
import Domain
import Foundation
import Networking
import NovaCore
import Routing

/// Composition root. The only place that knows concrete types; everything else sees protocols.
///
/// Launch-time discipline: `init` only allocates small objects — no disk, no network, no Keychain.
/// All I/O (session restore, cart hydration) happens in `bootstrap()`, which runs *after* the
/// first frame is on screen.
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
    public let router: Router
    public let session: SessionStore
    public let cart: CartStore
    public let wishlist: WishlistStore
    public let recentlyViewed: RecentlyViewedStore
    public let searchHistory: SearchHistoryStore

    public init(configuration: AppConfiguration) {
        self.configuration = configuration
        let latency = configuration.simulatedLatency
        let inMemory = configuration.isUITesting

        let transport: any HTTPTransport = switch configuration.environment {
        case .fixtures: FixtureTransport(latency: latency)
        case .production: URLSessionTransport()
        }
        let client = APIClient(baseURL: configuration.apiBaseURL, transport: transport)

        func store<Value: Codable & Sendable>(_ name: String, _: Value.Type) -> any Persisting<Value> {
            inMemory ? InMemoryStore<Value>() : FileStore<Value>(filename: name)
        }

        catalog = RemoteCatalogRepository(client: client)
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

        router = Router()
        session = SessionStore(auth: auth)
        cart = CartStore(persistence: store("cart", [CartItem].self), couponService: LocalCouponService(latency: latency))
        wishlist = WishlistStore(persistence: store("wishlist", [Product].self))
        recentlyViewed = RecentlyViewedStore(persistence: store("recently-viewed", [Product].self))
        searchHistory = SearchHistoryStore(persistence: store("search-history", [String].self))

        router.isAuthenticated = { [unowned session] in session.isSignedIn }
    }

    public static func live() -> AppContainer {
        AppContainer(configuration: .current)
    }

    /// Post-first-frame work. Independent hydrations run concurrently in a task group.
    public func bootstrap() async {
        await Perf.measure("Launch.Bootstrap") {
            async let restore: Void = session.restore()
            async let cartLoad: Void = cart.hydrate()
            async let wishlistLoad: Void = wishlist.hydrate()
            async let recentsLoad: Void = recentlyViewed.hydrate()
            async let historyLoad: Void = searchHistory.hydrate()
            _ = await (restore, cartLoad, wishlistLoad, recentsLoad, historyLoad)
        }
        if configuration.startSignedIn, !session.isSignedIn {
            try? await session.signIn(email: "olivia.chen@novashop.example", password: "password123")
            _ = try? await profile.save(Address(
                fullName: "Olivia Chen", line1: "123 Maple Street", city: "San Francisco", state: "CA", postalCode: "94110", isDefault: true
            ))
        }
    }
}
