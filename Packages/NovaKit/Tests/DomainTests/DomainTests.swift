@testable import Domain
import Foundation
import NovaCore
import Testing
import TestSupport

// MARK: - Filtering & sorting

@Suite("ProductFilterEngine")
struct ProductFilterEngineTests {
    let products: [Product] = [
        .fixture(id: "a", name: "Amelie Floral Midi Dress", price: 129, category: "dresses", style: "Midi", popularity: 10),
        .fixture(id: "b", name: "Isla Linen Dress", price: 99, category: "dresses", style: "Maxi", popularity: 50),
        .fixture(id: "c", name: "Luna Linen Tee", price: 39, category: "tops", style: "Tee", sizes: [.small], popularity: 90),
        .fixture(
            id: "d", name: "Scarlet Gown", price: 189, compareAtPrice: 220, category: "dresses", style: "Formal",
            inStock: false, popularity: 0
        ),
    ]

    @Test("Text search matches every token, case-insensitively")
    func textSearch() {
        let result = ProductFilterEngine.apply(ProductQuery(text: "LINEN dress"), to: products)
        #expect(result.map(\.id.rawValue) == ["b"])
    }

    @Test("Filters compose with AND semantics")
    func composedFilters() {
        let query = ProductQuery(categoryIDs: ["dresses"], priceRange: 90 ... 150)
        #expect(ProductFilterEngine.apply(query, to: products).map(\.id.rawValue) == ["a", "b"])
    }

    @Test("Size filter matches any overlapping size")
    func sizeFilter() {
        let query = ProductQuery(sizes: [.small], inStockOnly: true)
        #expect(ProductFilterEngine.apply(query, to: products).count == 3)
    }

    @Test("On sale / in stock toggles")
    func saleAndStock() {
        #expect(ProductFilterEngine.apply(ProductQuery(onSaleOnly: true), to: products).map(\.id.rawValue) == ["d"])
        #expect(ProductFilterEngine.apply(ProductQuery(inStockOnly: true), to: products).count == 3)
    }

    @Test("Sorting", arguments: [
        (SortOption.priceLowToHigh, ["c", "b", "a", "d"]),
        (SortOption.priceHighToLow, ["d", "a", "b", "c"]),
        (SortOption.bestSelling, ["c", "b", "a", "d"]),
        (SortOption.featured, ["a", "b", "c", "d"]),
    ])
    func sorting(option: SortOption, expected: [String]) {
        #expect(ProductFilterEngine.apply(ProductQuery(sort: option), to: products).map(\.id.rawValue) == expected)
    }

    @Test("Active filter count ignores text and sort")
    func activeFilterCount() {
        var query = ProductQuery(text: "linen", sort: .rating)
        #expect(query.activeFilterCount == 0)
        query.sizes = [.medium]
        query.onSaleOnly = true
        #expect(query.activeFilterCount == 2)
        #expect(query.resettingFilters().activeFilterCount == 0)
        #expect(query.resettingFilters().text == "linen")
    }

    @Test("Search over 10k products stays within budget")
    func searchPerformanceBudget() {
        let catalog = (0 ..< 10000).map { Product.fixture(id: "p\($0)", name: "Product \($0) linen", price: Decimal($0 % 300)) }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = ProductFilterEngine.apply(ProductQuery(text: "linen", priceRange: 50 ... 150, sort: .priceLowToHigh), to: catalog)
        }
        // Generous budget for CI simulators; catches accidental O(n²) regressions.
        #expect(elapsed < .milliseconds(500))
    }
}

// MARK: - Pricing

@Suite("PricingCalculator")
struct PricingCalculatorTests {
    let items = [
        CartItem(product: .fixture(id: "a", price: 129), color: nil, size: .medium),
        CartItem(product: .fixture(id: "b", price: 89), color: nil, size: .small),
        CartItem(product: .fixture(id: "c", price: 59), color: nil, size: .oneSize),
    ]

    @Test("SUMMER20 on $277 matches the design exactly: -$55.40 → $221.60")
    func designNumbers() {
        let breakdown = PricingCalculator.breakdown(items: items, coupon: Coupon(code: "SUMMER20", kind: .percentage(0.2)), shipping: nil)
        #expect(breakdown.subtotal == 277)
        #expect(breakdown.discount == Decimal(string: "55.40"))
        #expect(breakdown.total == Decimal(string: "221.60"))
        #expect(breakdown.shipping == nil)
        #expect(breakdown.tax == 0, "Tax is unknown until a shipping destination is chosen")
    }

    @Test("Express shipping and tax once shipping is known")
    func shippingAndTax() {
        let breakdown = PricingCalculator.breakdown(items: items, coupon: nil, shipping: .express, taxRate: 0.1)
        #expect(breakdown.shipping == 12)
        #expect(breakdown.tax == Decimal(string: "27.70"))
        #expect(breakdown.total == Decimal(string: "316.70"))
    }

    @Test("Coupons below their minimum give no discount; fixed discounts never exceed subtotal")
    func couponRules() {
        let minimum = Coupon(code: "BIG", kind: .fixedAmount(50), minimumSubtotal: 500)
        #expect(PricingCalculator.discount(for: minimum, subtotal: 277) == 0)
        let huge = Coupon(code: "HUGE", kind: .fixedAmount(1000))
        #expect(PricingCalculator.discount(for: huge, subtotal: 277) == 277)
    }

    @Test("Banker's rounding to cents")
    func rounding() throws {
        #expect(try PricingCalculator.rounded(#require(Decimal(string: "10.125"))) == Decimal(string: "10.12"))
        #expect(try PricingCalculator.rounded(#require(Decimal(string: "10.135"))) == Decimal(string: "10.14"))
    }
}

// MARK: - Validation

@Suite("Validation")
struct ValidationTests {
    @Test("Email", arguments: [
        ("olivia@novashop.com", true), ("o.chen+shop@mail.co.uk", true),
        ("", false), ("olivia", false), ("olivia@", false), ("@novashop.com", false), ("olivia@novashop", false), ("oli via@x.com", false),
    ])
    func email(input: String, isValid: Bool) {
        #expect((Validation.email(input) == nil) == isValid)
    }

    @Test("Luhn card numbers", arguments: [
        ("4242 4242 4242 4242", true), ("5555555555554444", true), ("378282246310005", true),
        ("4242 4242 4242 4241", false), ("1234", false), ("", false),
    ])
    func cardNumber(input: String, isValid: Bool) {
        #expect((Validation.cardNumber(input) == nil) == isValid)
    }

    @Test("Card brand detection")
    func brand() {
        #expect(Validation.brand(forCardNumber: "4242") == .visa)
        #expect(Validation.brand(forCardNumber: "5555 5555") == .mastercard)
        #expect(Validation.brand(forCardNumber: "2221 0000") == .mastercard)
        #expect(Validation.brand(forCardNumber: "3782") == .amex)
        #expect(Validation.brand(forCardNumber: "6011") == .discover)
    }

    @Test("Expiry is validated against an injected date")
    func expiry() throws {
        let now = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 25)))
        #expect(Validation.expiry("09/26", now: now) == nil)
        #expect(Validation.expiry("12/30", now: now) == nil)
        #expect(Validation.expiry("08/26", now: now) == .expiredCard)
        #expect(Validation.expiry("13/27", now: now) == .invalidExpiry)
        #expect(Validation.expiry("1227", now: now) == .invalidExpiry)
    }

    @Test("ZIP and ZIP+4", arguments: [
        ("10001", true), ("10001-1234", true), ("100011234", true), (" 10001 ", true),
        ("1000", false), ("10001-12", false), ("ABCDE", false), ("", false),
    ])
    func postalCode(input: String, isValid: Bool) {
        #expect((Validation.postalCode(input) == nil) == isValid)
    }

    @Test("All 50 states plus DC are selectable")
    func usStates() {
        #expect(Validation.usStates.count == 51)
        #expect(Set(Validation.usStates).count == 51)
        #expect(Validation.usStates.contains("NJ"))
    }

    @Test("State search matches names and exact codes")
    func stateSearch() {
        #expect(USState.search("jersey").map(\.code) == ["NJ"])
        #expect(USState.search("ny").map(\.code) == ["NY"])
        #expect(USState.search("north").map(\.code) == ["NC", "ND"])
        #expect(USState.search("").count == 51)
    }

    @Test("CVV length depends on brand")
    func cvv() {
        #expect(Validation.cvv("123", brand: .visa) == nil)
        #expect(Validation.cvv("1234", brand: .amex) == nil)
        #expect(Validation.cvv("1234", brand: .visa) == .invalidCVV)
    }

    @Test("Card input formatting")
    func formatting() {
        #expect(CardFormatter.formatNumber("4242424242424242") == "4242 4242 4242 4242")
        #expect(CardFormatter.formatNumber("4242-42") == "4242 42")
        #expect(CardFormatter.formatExpiry("1227") == "12/27")
        #expect(CardFormatter.formatExpiry("1") == "1")
    }
}

// MARK: - Stores

@MainActor
@Suite("CartStore (local-first)")
struct CartStoreTests {
    let dress = Product.fixture(id: "dress", price: 129)

    func makeStore(_ repository: FakeLocalFirstRepository<CartItem> = FakeLocalFirstRepository()) -> CartStore {
        CartStore(repository: repository, couponService: FakeCouponService(), clock: ImmediateClock())
    }

    /// Lets a store sync (signed in, online, backend on).
    func allowSync(_ store: CartStore) {
        store.list.syncGate = { nil }
    }

    @Test("Adding the same variant merges lines; different sizes stay separate")
    func mergeLines() {
        let store = makeStore()
        store.add(dress, color: nil, size: .medium)
        store.add(dress, color: nil, size: .medium)
        store.add(dress, color: nil, size: .large)
        #expect(store.items.count == 2)
        #expect(store.itemCount == 3)
    }

    @Test("Quantity is clamped and zero removes the line")
    func quantity() {
        let store = makeStore()
        store.add(dress, color: nil, size: .medium)
        let id = store.items[0].id
        store.setQuantity(99, for: id)
        #expect(store.items[0].quantity == CartStore.maxQuantityPerLine)
        store.setQuantity(0, for: id)
        #expect(store.isEmpty)
    }

    @Test("Mutations are instant in the UI and land on the repository in order")
    func optimisticAndOrdered() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        let store = makeStore(repository)
        for _ in 0 ..< 5 {
            store.add(dress, color: nil, size: .medium)
        }
        #expect(store.items.first?.quantity == 5, "UI updated synchronously, before any I/O")
        store.setQuantity(2, for: store.items[0].id)
        await store.flush()
        #expect(await repository.local.first?.quantity == 2, "Last write wins on disk too")
        #expect(store.pendingItemIDs.count == 1)
    }

    @Test("Signed out: nothing syncs and the bag says it's on this device")
    func localOnly() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        let store = makeStore(repository)
        store.add(dress, color: nil, size: .medium)
        await store.sync()
        #expect(store.syncStatus == .localOnly)
        #expect(await repository.syncCount == 0)
    }

    @Test("Offline with changes: waits for the network instead of failing")
    func offlineWaits() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        let store = makeStore(repository)
        store.list.syncGate = { .waitingForNetwork }
        store.add(dress, color: nil, size: .medium)
        await store.sync()
        #expect(store.syncStatus == .waitingForNetwork)
        #expect(await repository.syncCount == 0)
        #expect(!store.pendingItemIDs.isEmpty)
    }

    @Test("Online: syncs, clears pending state and adopts the server's view")
    func syncsOnline() async {
        let fromOtherDevice = CartItem(product: .fixture(id: "coat", price: 200), color: nil, size: .small)
        let repository = FakeLocalFirstRepository<CartItem>(server: [fromOtherDevice])
        let store = makeStore(repository)
        allowSync(store)
        store.add(dress, color: nil, size: .medium)
        await store.sync()

        if case .synced = store.syncStatus {} else {
            Issue.record("Expected synced, got \(store.syncStatus)")
        }
        #expect(store.pendingItemIDs.isEmpty)
        #expect(Set(store.items.map(\.product.id.rawValue)) == ["coat", "dress"], "Server-side lines merged in")
    }

    @Test("Transient failure keeps changes pending and reports a retrying state")
    func failureKeepsPending() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        await repository.failSync(with: URLError(.badServerResponse))
        let store = makeStore(repository)
        allowSync(store)
        store.add(dress, color: nil, size: .medium)
        await store.sync()
        if case .failed = store.syncStatus {} else {
            Issue.record("Expected failed, got \(store.syncStatus)")
        }
        #expect(store.items.count == 1, "Nothing lost locally")
        #expect(!store.pendingItemIDs.isEmpty)
    }

    @Test("Lines the server rejects are removed and explained once")
    func rejection() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        let store = makeStore(repository)
        allowSync(store)
        store.add(dress, color: nil, size: .medium)
        await repository.reject([store.items[0].id])
        await store.sync()
        #expect(store.isEmpty)
        #expect(store.rejectionNotice?.contains("Amelie Floral Midi Dress") == true)
        store.dismissRejectionNotice()
        #expect(store.rejectionNotice == nil)
    }

    @Test("Checkout sync: offline is a typed error, not a silent stale order")
    func checkoutSync() async {
        let store = makeStore()
        store.list.syncGate = { .waitingForNetwork }
        store.add(dress, color: nil, size: .medium)
        await #expect(throws: CheckoutError.offline) { try await store.syncForCheckout() }
    }

    @Test("Sign-out wipes this account's local bag")
    func signOutWipes() async {
        let repository = FakeLocalFirstRepository<CartItem>()
        let store = makeStore(repository)
        store.add(dress, color: nil, size: .medium)
        await store.removeAllLocally()
        #expect(store.isEmpty)
        #expect(await repository.local.isEmpty)
    }

    @Test("Coupon applies, and is dropped when the cart falls below its minimum")
    func coupons() async throws {
        let store = makeStore()
        store.add(.fixture(id: "coat", price: 350), color: nil, size: .medium)
        try await store.applyCoupon(code: "BIG50")
        #expect(store.breakdown(shipping: nil).discount == 50)

        store.setQuantity(0, for: store.items[0].id)
        #expect(store.coupon == nil)
    }

    @Test("Invalid coupon surfaces a typed error")
    func invalidCoupon() async {
        let store = makeStore()
        store.add(dress, color: nil, size: .medium)
        await #expect(throws: CouponError.notFound) { try await store.applyCoupon(code: "NOPE") }
        #expect(store.coupon == nil)
    }
}

@MainActor
@Suite("Collection stores")
struct CollectionStoreTests {
    @Test("Wishlist toggles, answers contains in O(1), newest first")
    func wishlist() async {
        let repository = FakeLocalFirstRepository<Product>()
        let store = WishlistStore(repository: repository, clock: ImmediateClock())
        let first = Product.fixture(id: "a")
        let second = Product.fixture(id: "b")
        store.toggle(first)
        store.toggle(second)
        #expect(store.products.map(\.id.rawValue) == ["b", "a"])
        #expect(store.contains(first.id))
        store.toggle(first)
        #expect(!store.contains(first.id))
        await store.flush()
        #expect(await repository.local.map(\.id.rawValue) == ["b"])
    }

    @Test("Recently viewed is de-duplicated, most recent first and capped")
    func recents() {
        let store = RecentlyViewedStore(persistence: InMemoryPersistence())
        for index in 0 ..< 25 {
            store.record(.fixture(id: "p\(index)"))
        }
        store.record(.fixture(id: "p10"))
        #expect(store.products.count == RecentlyViewedStore.capacity)
        #expect(store.products.first?.id.rawValue == "p10")
        #expect(store.products.filter { $0.id.rawValue == "p10" }.count == 1)
    }

    @Test("Search history de-dupes case-insensitively")
    func searchHistory() {
        let store = SearchHistoryStore(persistence: InMemoryPersistence())
        store.record("Linen dress")
        store.record("sunglasses")
        store.record("LINEN DRESS")
        store.record("   ")
        #expect(store.terms == ["LINEN DRESS", "sunglasses"])
    }
}

@MainActor
@Suite("SessionStore")
struct SessionStoreTests {
    @Test("Restores a persisted session")
    func restore() async {
        let store = SessionStore(auth: FakeAuthService(user: User(name: "Olivia Chen", email: "o@c.com")))
        #expect(store.state == .restoring)
        await store.restore()
        #expect(store.user?.initials == "OC")
    }

    @Test("Failed sign in leaves the user signed out")
    func failedSignIn() async {
        let store = SessionStore(auth: FakeAuthService())
        await store.restore()
        await #expect(throws: AuthError.invalidCredentials) {
            try await store.signIn(email: "o@c.com", password: "wrong")
        }
        #expect(store.state == .signedOut)
    }
}

@Suite("AppConfiguration")
struct AppConfigurationTests {
    @Test("Supabase turns on only with host + key, never under UI tests")
    func backendSelection() {
        let info: [String: Any] = [AppConfiguration.InfoKey.supabaseHost: "abc.supabase.co", AppConfiguration.InfoKey.supabaseKey: "pk"]
        let live = AppConfiguration.resolve(arguments: [], environment: [:], info: info)
        #expect(live.environment == .supabase)
        #expect(live.apiBaseURL.absoluteString == "https://abc.supabase.co")

        #expect(AppConfiguration.resolve(arguments: ["-ui-testing"], environment: [:], info: info).environment == .fixtures)
        #expect(AppConfiguration.resolve(arguments: [], environment: [:], info: [:]).environment == .fixtures)
        let missingKey: [String: Any] = [AppConfiguration.InfoKey.supabaseHost: "abc.supabase.co", AppConfiguration.InfoKey.supabaseKey: ""]
        #expect(AppConfiguration.resolve(arguments: [], environment: [:], info: missingKey).environment == .fixtures)
    }
}

@Suite("ReviewStats")
struct ReviewStatsTests {
    @Test("Average and distribution from a list")
    func computed() {
        let reviews = [5, 5, 4, 3].enumerated().map { index, rating in
            Review(id: "\(index)", productID: "p", author: "A", rating: rating, body: "", date: .now, isVerified: index.isMultiple(of: 2))
        }
        let stats = ReviewStats(reviews: reviews)
        #expect(stats.average == 4.3)
        #expect(stats.distribution[5] == 0.5)
        #expect(stats.distribution[1] == 0)
        #expect(ReviewFilter.verified.apply(to: reviews).count == 2)
    }
}
