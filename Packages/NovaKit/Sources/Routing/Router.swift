import Domain
import Foundation
import NovaCore
import Observation

public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, shop, search, wishlist, account
}

/// Every push destination in the app, as a value. Features emit routes; only the composition root
/// (`AppFeature`) knows which view renders each one — so features never import each other.
public enum Route: Hashable, Sendable {
    case product(Product.ID, preview: Product?)
    case category(ProductCategory)
    case collection(EditorialCollection)
    case productList(title: String, query: ProductQuery)
    case searchResults(ProductQuery)
    case reviews(Product)
    case cart
    case coupon
    case checkout
    case orderConfirmation(Order)
    case orders
    case order(Order)
    case returnRequest(Order)
    case recentlyViewed
    case addresses
    case addAddress
    case paymentMethods
    case notifications
    case settings

    /// Routes that require an account. Guests are shown sign-in first, then land here.
    public var requiresAuthentication: Bool {
        switch self {
        case .checkout, .orders, .order, .returnRequest, .addresses, .addAddress, .paymentMethods: true
        default: false
        }
    }
}

public enum SheetRoute: Identifiable, Hashable, Sendable {
    case auth(then: Route?)

    public var id: String {
        switch self {
        case .auth: "auth"
        }
    }
}

/// Navigation state for the whole app: selected tab, one stack per tab, and the modal sheet.
///
/// Pure state — no views — so every navigation rule (auth gating, deep links, re-tap-to-pop) is
/// unit-tested without UI, and state restoration is just encoding this object.
@MainActor
@Observable
public final class Router {
    public var selectedTab: AppTab = .home
    public var paths: [AppTab: [Route]] = [:]
    public var sheet: SheetRoute?

    /// Evaluated when a route requires auth. Injected so Routing does not depend on the session.
    @ObservationIgnored public var isAuthenticated: @MainActor () -> Bool = { false }

    public init() {}

    public func path(for tab: AppTab) -> [Route] {
        paths[tab] ?? []
    }

    public func setPath(_ path: [Route], for tab: AppTab) {
        paths[tab] = path
    }

    public func push(_ route: Route) {
        if route.requiresAuthentication, !isAuthenticated() {
            sheet = .auth(then: route)
            return
        }
        Log.navigation.debug("push \(String(describing: route), privacy: .public)")
        paths[selectedTab, default: []].append(route)
    }

    public func pop() {
        _ = paths[selectedTab]?.popLast()
    }

    public func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    /// Tapping the selected tab again pops to its root — the platform convention.
    public func select(_ tab: AppTab) {
        if tab == selectedTab {
            popToRoot(tab)
        } else {
            selectedTab = tab
        }
    }

    public func present(_ sheet: SheetRoute) {
        self.sheet = sheet
    }

    /// Called by the auth flow on success: dismiss and continue where the user was going.
    public func completeAuthentication() {
        guard case let .auth(pending) = sheet else { return }
        sheet = nil
        if let pending {
            push(pending)
        }
    }

    public func dismissSheet() {
        sheet = nil
    }

    // MARK: Deep links

    @discardableResult
    public func handle(_ link: DeepLink) -> Bool {
        sheet = nil
        switch link {
        case let .product(id):
            selectedTab = .home
            paths[.home] = [.product(id, preview: nil)]
        case let .search(text):
            selectedTab = .search
            paths[.search] = text.isEmpty ? [] : [.searchResults(ProductQuery(text: text))]
        case .cart:
            paths[selectedTab, default: []].append(.cart)
        case .orders:
            selectedTab = .account
            paths[.account] = []
            push(.orders)
        case let .tab(tab):
            selectedTab = tab
            popToRoot(tab)
        }
        return true
    }
}

/// External entry points: `novashop://product/amelie-floral-midi`, `novashop://search?q=linen`,
/// universal links `https://novashop.example/p/<id>`. Parsing is a pure function → table tests.
public enum DeepLink: Equatable, Sendable {
    case product(Product.ID)
    case search(String)
    case cart
    case orders
    case tab(AppTab)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var segments = url.pathComponents.filter { $0 != "/" }
        if components.scheme == "novashop", let host = components.host {
            segments.insert(host, at: 0)
        } else if components.scheme != "https" || components.host != "novashop.example" {
            return nil
        }

        switch segments.first {
        case "product", "p":
            guard segments.count >= 2 else { return nil }
            self = .product(Product.ID(segments[1]))
        case "search":
            self = .search(components.queryItems?.first { $0.name == "q" }?.value ?? "")
        case "cart", "bag":
            self = .cart
        case "orders":
            self = .orders
        case let name?:
            guard let tab = AppTab(rawValue: name) else { return nil }
            self = .tab(tab)
        case nil:
            return nil
        }
    }
}
