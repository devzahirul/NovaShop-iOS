import Domain
import Foundation
@testable import Routing
import Testing

@Suite("DeepLink parsing")
struct DeepLinkTests {
    @Test(arguments: [
        ("novashop://product/amelie-floral-midi", DeepLink.product("amelie-floral-midi")),
        ("https://novashop.example/p/isla-linen", DeepLink.product("isla-linen")),
        ("novashop://search?q=linen%20dress", DeepLink.search("linen dress")),
        ("novashop://cart", DeepLink.cart),
        ("novashop://orders", DeepLink.orders),
        ("novashop://wishlist", DeepLink.tab(.wishlist)),
    ])
    func parses(url: String, expected: DeepLink) throws {
        #expect(try DeepLink(url: #require(URL(string: url))) == expected)
    }

    @Test(arguments: ["https://evil.example/p/x", "novashop://unknown", "novashop://product", "mailto:hi@novashop.example"])
    func rejects(url: String) throws {
        #expect(try DeepLink(url: #require(URL(string: url))) == nil)
    }
}

@MainActor
@Suite("Router")
struct RouterTests {
    @Test("Pushes onto the selected tab's own stack")
    func perTabStacks() {
        let router = Router()
        router.push(.cart)
        router.select(.shop)
        router.push(.recentlyViewed)
        #expect(router.path(for: .home) == [.cart])
        #expect(router.path(for: .shop) == [.recentlyViewed])
    }

    @Test("Re-selecting the current tab pops to root")
    func reselectPops() {
        let router = Router()
        router.push(.cart)
        router.push(.coupon)
        router.select(.home)
        #expect(router.path(for: .home).isEmpty)
    }

    @Test("Guests are sent to sign in, then resume where they were going")
    func authGate() {
        var signedIn = false
        let router = Router()
        router.isAuthenticated = { signedIn }

        router.push(.checkout)
        #expect(router.sheet == .auth(then: .checkout))
        #expect(router.path(for: .home).isEmpty)

        signedIn = true
        router.completeAuthentication()
        #expect(router.sheet == nil)
        #expect(router.path(for: .home) == [.checkout])
    }

    @Test("Deep links select the right tab and stack")
    func deepLinks() {
        let router = Router()
        router.present(.auth(then: nil))
        router.handle(.search("linen"))
        #expect(router.sheet == nil)
        #expect(router.selectedTab == .search)
        #expect(router.path(for: .search) == [.searchResults(ProductQuery(text: "linen"))])
    }
}
