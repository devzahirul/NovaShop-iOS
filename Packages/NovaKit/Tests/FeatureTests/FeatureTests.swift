@testable import AuthFeature
@testable import CartFeature
@testable import CatalogFeature
@testable import CheckoutFeature
import Domain
import Foundation
@testable import HomeFeature
import NovaCore
@testable import ProductFeature
import Testing
import TestSupport

// View-model tests: the UI's behaviour without rendering a single view.

@MainActor
@Suite("HomeViewModel")
struct HomeViewModelTests {
    @Test("Loads new arrivals (newest first) and best sellers")
    func loads() async {
        let catalog = FakeCatalogRepository(products: [
            .fixture(id: "old", tags: [ProductTag.new], releasedAt: .distantPast, popularity: 1),
            .fixture(id: "fresh", tags: [ProductTag.new], releasedAt: .now, popularity: 5),
            .fixture(id: "hit", popularity: 99),
        ])
        let viewModel = HomeViewModel(catalog: catalog)
        await viewModel.load()
        let content = viewModel.state.value
        #expect(content?.newArrivals.map(\.id.rawValue) == ["fresh", "old"])
        #expect(content?.bestSellers.first?.id.rawValue == "hit")
    }

    @Test("Failures become a user-facing error state")
    func failure() async {
        let viewModel = HomeViewModel(catalog: FakeCatalogRepository(error: URLError(.notConnectedToInternet)))
        await viewModel.load()
        #expect(viewModel.state.error == .generic)
    }
}

@MainActor
@Suite("SearchViewModel")
struct SearchViewModelTests {
    func make(_ catalog: FakeCatalogRepository = FakeCatalogRepository(products: [.fixture(id: "isla", name: "Isla Linen Dress")]))
        -> SearchViewModel {
        SearchViewModel(catalog: catalog, history: SearchHistoryStore(persistence: InMemoryPersistence()), clock: ImmediateClock())
    }

    @Test("Type-ahead needs two characters")
    func minimumLength() async {
        let catalog = FakeCatalogRepository(products: [.fixture(name: "Isla Linen Dress")])
        let viewModel = make(catalog)
        viewModel.text = "l"
        await viewModel.updateSuggestions()
        #expect(viewModel.suggestions.isEmpty)
        #expect(await catalog.searchCalls.isEmpty)
    }

    @Test("Suggestions come from the catalog search")
    func suggestions() async {
        let viewModel = make()
        viewModel.text = "linen"
        await viewModel.updateSuggestions()
        #expect(viewModel.suggestions.map(\.id.rawValue) == ["isla"])
    }

    @Test("A cancelled (superseded) keystroke never hits the network")
    func debounceCancellation() async {
        let catalog = FakeCatalogRepository()
        let viewModel = SearchViewModel(
            catalog: catalog, history: SearchHistoryStore(persistence: InMemoryPersistence()),
            clock: ContinuousClock(), debounce: .seconds(10)
        )
        viewModel.text = "lin"
        let task = Task { await viewModel.updateSuggestions() }
        task.cancel()
        await task.value
        #expect(await catalog.searchCalls.isEmpty)
    }

    @Test("Submitting records history and returns a query")
    func submit() {
        let viewModel = make()
        #expect(viewModel.submit("  Sunglasses ") == ProductQuery(text: "Sunglasses"))
        #expect(viewModel.recent == ["Sunglasses"])
        #expect(viewModel.submit("   ") == nil)
    }
}

@MainActor
@Suite("ProductListingViewModel")
struct ProductListingViewModelTests {
    @Test("Live filter count matches what Apply will show")
    func liveCount() async {
        let catalog = FakeCatalogRepository(products: [
            .fixture(id: "a", price: 40), .fixture(id: "b", price: 90, compareAtPrice: 120), .fixture(id: "c", price: 180),
        ])
        let viewModel = ProductListingViewModel(query: ProductQuery(), catalog: catalog)
        await viewModel.load()
        var draft = viewModel.query
        draft.onSaleOnly = true
        #expect(viewModel.resultCount(for: draft) == 1)
        #expect(viewModel.priceBounds == 40 ... 180)
    }

    @Test("Style chips narrow the query")
    func styles() {
        let viewModel = ProductListingViewModel(query: ProductQuery(categoryIDs: ["dresses"]), catalog: FakeCatalogRepository())
        viewModel.setStyle("Maxi")
        #expect(viewModel.query.styles == ["Maxi"])
        viewModel.setStyle(nil)
        #expect(viewModel.query.styles.isEmpty)
    }
}

@MainActor
@Suite("ProductDetailViewModel")
struct ProductDetailViewModelTests {
    let dress = Product.fixture(id: "dress", sizes: [.small, .medium])
    let bag = Product.fixture(id: "bag", category: "bags", sizes: [.oneSize])

    func make(_ product: Product, cart: CartStore, recents: RecentlyViewedStore? = nil) -> ProductDetailViewModel {
        ProductDetailViewModel(
            productID: product.id, preview: product, catalog: FakeCatalogRepository(products: [dress, bag]), cart: cart,
            recentlyViewed: recents ?? RecentlyViewedStore(persistence: InMemoryPersistence())
        )
    }

    func makeCart() -> CartStore {
        CartStore(repository: FakeLocalFirstRepository(), couponService: FakeCouponService(), clock: ImmediateClock())
    }

    @Test("Adding without a size shows the inline error and adds nothing")
    func requiresSize() {
        let cart = makeCart()
        let viewModel = make(dress, cart: cart)
        #expect(viewModel.addToCart() == .needsSize)
        #expect(viewModel.showSizeError)
        #expect(cart.isEmpty)

        viewModel.selectSize(.medium)
        #expect(!viewModel.showSizeError)
        #expect(viewModel.addToCart() == .added)
        #expect(cart.items.first?.size == .medium)
    }

    @Test("One-size products are preselected")
    func oneSize() {
        let cart = makeCart()
        #expect(make(bag, cart: cart).addToCart() == .added)
    }

    @Test("Viewing a product records it in recently viewed")
    func recordsRecent() async {
        let recents = RecentlyViewedStore(persistence: InMemoryPersistence())
        let viewModel = make(dress, cart: makeCart(), recents: recents)
        await viewModel.load()
        #expect(recents.products.first?.id == dress.id)
        #expect(viewModel.related.map(\.id).contains(dress.id) == false)
    }
}

@MainActor
@Suite("CheckoutViewModel")
struct CheckoutViewModelTests {
    func makeCart() -> CartStore {
        let cart = CartStore(repository: FakeLocalFirstRepository(), couponService: FakeCouponService(), clock: ImmediateClock())
        cart.add(.fixture(price: 100), color: nil, size: .medium)
        return cart
    }

    @Test("Happy path: shipping → payment → review → order placed, cart cleared")
    func happyPath() async {
        let cart = makeCart()
        let orders = FakeOrderService()
        let viewModel = CheckoutViewModel(cart: cart, profile: FakeProfileRepository(addresses: [.fixture()]), orders: orders)
        await viewModel.load()

        #expect(viewModel.selectedAddress != nil, "Default address is preselected")
        viewModel.shipping = .express
        viewModel.advance()
        #expect(viewModel.step == .payment)
        #expect(viewModel.selectedPayment == .applePay)
        viewModel.advance()
        #expect(viewModel.step == .review)

        await viewModel.placeOrder()
        #expect(viewModel.placedOrder?.shipping == .express)
        #expect(cart.isEmpty)
        #expect(await orders.placed.count == 1)
    }

    @Test("Offline: checkout is refused up front with a clear, typed message")
    func offlineCheckout() async {
        let orders = FakeOrderService()
        let viewModel = CheckoutViewModel(
            cart: makeCart(), profile: FakeProfileRepository(addresses: [.fixture()]), orders: orders, isOnline: { false }
        )
        await viewModel.load()
        viewModel.advance()
        viewModel.advance()
        #expect(viewModel.isOffline)
        await viewModel.placeOrder()
        #expect(viewModel.phase == .failed(CheckoutError.offline.userFacing))
        #expect(await orders.attemptedKeys.isEmpty, "Never hits the server")
    }

    @Test("Retrying after a failure reuses the idempotency key; success rotates it")
    func idempotencyKey() async throws {
        let orders = FakeOrderService(shouldDecline: true)
        let viewModel = CheckoutViewModel(cart: makeCart(), profile: FakeProfileRepository(addresses: [.fixture()]), orders: orders)
        await viewModel.load()
        viewModel.advance()
        viewModel.advance()
        await viewModel.placeOrder() // declined
        viewModel.dismissError()
        await orders.setDecline(false)
        await viewModel.placeOrder() // retried → same key → server would dedupe
        let keys = await orders.attemptedKeys
        try #require(keys.count == 2)
        #expect(keys[0] == keys[1])
        #expect(viewModel.placedOrder != nil)
    }

    @Test("Cannot continue without an address")
    func needsAddress() async {
        let viewModel = CheckoutViewModel(cart: makeCart(), profile: FakeProfileRepository(), orders: FakeOrderService())
        await viewModel.load()
        #expect(!viewModel.canContinue)
        viewModel.advance()
        #expect(viewModel.step == .shipping)
    }

    @Test("A declined payment keeps the cart and shows an error")
    func declined() async {
        let cart = makeCart()
        let viewModel = CheckoutViewModel(
            cart: cart,
            profile: FakeProfileRepository(addresses: [.fixture()]),
            orders: FakeOrderService(shouldDecline: true)
        )
        await viewModel.load()
        viewModel.advance()
        viewModel.advance()
        await viewModel.placeOrder()
        #expect(viewModel.phase == .failed(PaymentError.declined.userFacing))
        #expect(!cart.isEmpty)
        viewModel.dismissError()
        #expect(viewModel.phase == .editing)
    }

    @Test("Back walks the steps and reports when to pop")
    func back() async {
        let viewModel = CheckoutViewModel(
            cart: makeCart(),
            profile: FakeProfileRepository(addresses: [.fixture()]),
            orders: FakeOrderService()
        )
        await viewModel.load()
        viewModel.advance()
        #expect(viewModel.back())
        #expect(!viewModel.back())
    }

    @Test("A card added without saving is still usable for this order, and selected")
    func oneTimeCard() async {
        let profile = FakeProfileRepository(addresses: [.fixture()])
        let orders = FakeOrderService()
        let viewModel = CheckoutViewModel(cart: makeCart(), profile: profile, orders: orders)
        await viewModel.load()
        let card = PaymentMethod(kind: .card(brand: .visa, last4: "4242", expiry: "12/30", holder: "Olivia"))

        viewModel.useCard(card) // "Save for later" was off → never persisted
        #expect(viewModel.selectedPaymentID == card.id)
        #expect(viewModel.paymentOptions.first == card)
        #expect(await profile.paymentMethods().isEmpty)

        viewModel.advance()
        viewModel.advance()
        await viewModel.placeOrder()
        #expect(await orders.placed.first?.payment == card)
    }

    @Test("Adding a card once shows it once (saved card must not also linger as one-time)")
    func cardAddedOnceShowsOnce() async throws {
        let profile = FakeProfileRepository(addresses: [.fixture()])
        let viewModel = CheckoutViewModel(cart: makeCart(), profile: profile, orders: FakeOrderService())
        await viewModel.load()
        let card = PaymentMethod(kind: .card(brand: .visa, last4: "4242", expiry: "12/30", holder: "Olivia"))
        _ = try await profile.save(card)   // AddCardView saved it ("save for later" on)…
        viewModel.useCard(card)            // …then handed it to checkout
        await viewModel.load()
        let cards = viewModel.paymentOptions.filter { if case .card = $0.kind { true } else { false } }
        #expect(cards.count == 1, "Got \(cards.count): \(cards.map(\.title))")
    }

    @Test("Newly added card is auto-selected on reload")
    func autoSelectNewCard() async throws {
        let profile = FakeProfileRepository(addresses: [.fixture()])
        let viewModel = CheckoutViewModel(cart: makeCart(), profile: profile, orders: FakeOrderService())
        await viewModel.load()
        let card = PaymentMethod(kind: .card(brand: .visa, last4: "4242", expiry: "12/30", holder: "Olivia"))
        _ = try await profile.save(card)
        await viewModel.load()
        #expect(viewModel.selectedPaymentID == card.id)
    }
}

@MainActor
@Suite("Forms")
struct FormTests {
    @Test("Add card validates and stores only brand + last four")
    func addCard() async throws {
        let profile = FakeProfileRepository()
        let now = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let viewModel = AddCardViewModel(profile: profile, now: { now })
        viewModel.number = "4242424242424242"
        #expect(viewModel.number == "4242 4242 4242 4242", "Formatted as the user types")
        viewModel.expiry = "1230"
        #expect(viewModel.expiry == "12/30")
        #expect(await viewModel.save() == nil, "Missing name + CVV")
        #expect(viewModel.errors.keys.sorted { "\($0)" < "\($1)" } == [.cvv, .name])

        viewModel.holder = "Olivia Chen"
        viewModel.cvv = "123"
        let method = try #require(await viewModel.save())
        #expect(method.kind == .card(brand: .visa, last4: "4242", expiry: "12/30", holder: "Olivia Chen"))
        #expect(await profile.paymentMethods().count == 1)
    }

    @Test("Address: a rejected save explains itself and points at the first bad field")
    func addressRejectedSave() async {
        let profile = FakeProfileRepository()
        let viewModel = AddAddressViewModel(profile: profile, prefillName: "Olivia Chen")
        viewModel.line1 = "456 Oak Avenue"
        viewModel.city = "New York"
        viewModel.postalCode = "10001"

        #expect(await viewModel.save() == false, "State missing")
        #expect(viewModel.failedSubmitCount == 1)
        #expect(viewModel.firstInvalidField == .state)
        #expect(viewModel.errorSummary == "State is required.")
        #expect(await profile.addresses().isEmpty)

        viewModel.state = "NY"
        #expect(viewModel.errors.isEmpty, "Fixing a field clears its error immediately")
        #expect(await viewModel.save())
        #expect(await profile.addresses().first?.state == "NY")
    }

    @Test("Address: field order drives which error is scrolled to")
    func addressFirstInvalidField() async {
        let viewModel = AddAddressViewModel(profile: FakeProfileRepository())
        #expect(await viewModel.save() == false)
        #expect(viewModel.firstInvalidField == .name)
        #expect(viewModel.errorSummary == "Please fix the 5 highlighted fields.")
    }

    @Test("Card: rejected save is signalled; editing clears the field's error")
    func cardRejectedSave() async {
        let viewModel = AddCardViewModel(profile: FakeProfileRepository())
        viewModel.number = "4242 4242 4242 4241"
        #expect(await viewModel.save() == nil)
        #expect(viewModel.failedSubmitCount == 1)
        #expect(viewModel.firstInvalidField == .number)
        viewModel.number = "4242424242424242"
        #expect(viewModel.errors[.number] == nil)
    }

    @Test("Coupon view model maps errors for display")
    func coupon() async {
        let cart = CartStore(repository: FakeLocalFirstRepository(), couponService: FakeCouponService(), clock: ImmediateClock())
        cart.add(.fixture(price: 100), color: nil, size: .medium)
        let viewModel = CouponViewModel(cart: cart)
        viewModel.code = "WRONG"
        await viewModel.apply()
        #expect(viewModel.error?.title == "Invalid code")
        viewModel.code = "summer20"
        await viewModel.apply()
        #expect(viewModel.error == nil)
        #expect(cart.breakdown(shipping: nil).discount == 20)
    }

    @Test("Sign in validates locally before calling the server")
    func signInValidation() async {
        let viewModel = SignInViewModel(session: SessionStore(auth: FakeAuthService()))
        viewModel.email = "not-an-email"
        viewModel.password = "short"
        #expect(await viewModel.signIn() == false)
        #expect(viewModel.fieldErrors[.email] != nil)
        #expect(viewModel.fieldErrors[.password] != nil)

        viewModel.email = "olivia@example.com"
        viewModel.password = "password123"
        #expect(await viewModel.signIn())
    }

    @Test("Sign up surfaces duplicate accounts")
    func signUpDuplicate() async {
        let viewModel = SignUpViewModel(session: SessionStore(auth: FakeAuthService()))
        viewModel.name = "Olivia"
        viewModel.email = "taken@example.com"
        viewModel.password = "password123"
        viewModel.acceptedTerms = true
        #expect(await viewModel.signUp() == false)
        #expect(viewModel.error == AuthError.emailAlreadyInUse.userFacing)
    }
}
