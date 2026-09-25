import Domain
import Foundation
import NovaCore

// Shared test doubles. Hand-written fakes (not a mocking framework): they are tiny, type-checked,
// and behave like the real adapters, so tests read as behaviour, not as call choreography.

// MARK: - Fixtures

public extension Product {
    static func fixture(
        id: String = "p1",
        name: String = "Amelie Floral Midi Dress",
        price: Decimal = 129,
        compareAtPrice: Decimal? = nil,
        category: String = "dresses",
        style: String = "Midi",
        colors: [ProductColor] = [ProductColor(name: "Rust", hex: "#A0522D")],
        sizes: [Size] = [.xs, .small, .medium, .large],
        rating: Double = 4.8,
        reviewCount: Int = 320,
        tags: Set<String> = [],
        inStock: Bool = true,
        releasedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        popularity: Int = 100
    ) -> Product {
        Product(
            id: .init(id), name: name, price: price, compareAtPrice: compareAtPrice, categoryID: .init(category), style: style,
            imageURLs: [URL(string: "https://example.com/\(id).jpg")!], colors: colors, sizes: sizes, rating: rating,
            reviewCount: reviewCount, tags: tags, inStock: inStock, releasedAt: releasedAt, popularity: popularity
        )
    }
}

public extension Address {
    static func fixture(isDefault: Bool = true) -> Address {
        Address(
            fullName: "Olivia Chen",
            line1: "123 Maple Street",
            city: "San Francisco",
            state: "CA",
            postalCode: "94110",
            isDefault: isDefault
        )
    }
}

// MARK: - Persistence

public actor InMemoryPersistence<Value: Sendable>: Persisting {
    public private(set) var value: Value?
    public private(set) var saveCount = 0

    public init(_ value: Value? = nil) {
        self.value = value
    }

    public func load() async -> Value? {
        value
    }

    public func save(_ value: Value) async throws {
        self.value = value
        saveCount += 1
    }
}

// MARK: - Services

public actor FakeCatalogRepository: CatalogRepository {
    public var stubProducts: [Product]
    public var stubCategories: [ProductCategory]
    public var error: (any Error)?
    public private(set) var searchCalls: [ProductQuery] = []

    public init(products: [Product] = [], categories: [ProductCategory] = [], error: (any Error)? = nil) {
        stubProducts = products
        stubCategories = categories
        self.error = error
    }

    public func setError(_ error: (any Error)?) {
        self.error = error
    }

    public func categories() async throws -> [ProductCategory] {
        try throwIfNeeded()
        return stubCategories
    }

    public func products() async throws -> [Product] {
        try throwIfNeeded()
        return stubProducts
    }

    public func product(id: Product.ID) async throws -> Product {
        try throwIfNeeded()
        guard let product = stubProducts.first(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        return product
    }

    public func search(_ query: ProductQuery) async throws -> [Product] {
        searchCalls.append(query)
        try throwIfNeeded()
        return ProductFilterEngine.apply(query, to: stubProducts)
    }

    public func collections() async throws -> [EditorialCollection] {
        []
    }

    public func reviews(for _: Product.ID) async throws -> ReviewPage {
        ReviewPage(stats: ReviewStats(reviews: []), reviews: [])
    }

    public func popularSearches() async throws -> [String] {
        ["Linen dress"]
    }

    private func throwIfNeeded() throws {
        if let error {
            throw error
        }
    }
}

public struct FakeCouponService: CouponService {
    public init() {}

    public func validate(code: String, subtotal: Decimal) async throws -> Coupon {
        switch code.uppercased() {
        case "SUMMER20": return Coupon(code: "SUMMER20", kind: .percentage(0.2))
        case "BIG50":
            let coupon = Coupon(code: "BIG50", kind: .fixedAmount(50), minimumSubtotal: 300)
            guard subtotal >= coupon.minimumSubtotal else { throw CouponError.minimumNotMet(300) }
            return coupon
        default: throw CouponError.notFound
        }
    }
}

public actor FakeOrderService: OrderService {
    public var shouldDecline = false
    public private(set) var placed: [OrderDraft] = []

    public init(shouldDecline: Bool = false) {
        self.shouldDecline = shouldDecline
    }

    public func placeOrder(_ draft: OrderDraft) async throws -> Order {
        if shouldDecline {
            throw PaymentError.declined
        }
        placed.append(draft)
        return Order(
            number: "NS000001", items: draft.items, address: draft.address, payment: draft.payment, shipping: draft.shipping,
            pricing: PricingCalculator.breakdown(items: draft.items, coupon: draft.coupon, shipping: draft.shipping),
            placedAt: Date(timeIntervalSince1970: 0), status: .processing
        )
    }

    public func orders() async throws -> [Order] {
        []
    }
}

public actor FakeProfileRepository: ProfileRepository {
    private var storedAddresses: [Address]
    private var storedMethods: [PaymentMethod]

    public init(addresses: [Address] = [], methods: [PaymentMethod] = []) {
        storedAddresses = addresses
        storedMethods = methods
    }

    public func addresses() async -> [Address] {
        storedAddresses
    }

    public func save(_ address: Address) async throws -> [Address] {
        storedAddresses.append(address)
        return storedAddresses
    }

    public func deleteAddress(id: Address.ID) async throws -> [Address] {
        storedAddresses.removeAll { $0.id == id }
        return storedAddresses
    }

    public func paymentMethods() async -> [PaymentMethod] {
        storedMethods
    }

    public func save(_ method: PaymentMethod) async throws -> [PaymentMethod] {
        storedMethods.insert(method, at: 0)
        return storedMethods
    }
}

public actor FakeAuthService: AuthService {
    public var user: User?
    public init(user: User? = nil) {
        self.user = user
    }

    public func restoreSession() async -> User? {
        user
    }

    public func signIn(email: String, password: String) async throws -> User {
        guard password == "password123" else { throw AuthError.invalidCredentials }
        let user = User(name: "Olivia Chen", email: email)
        self.user = user
        return user
    }

    public func signUp(name: String, email: String, password _: String) async throws -> User {
        if email == "taken@example.com" {
            throw AuthError.emailAlreadyInUse
        }
        let user = User(name: name, email: email)
        self.user = user
        return user
    }

    public func signIn(with _: SocialProvider) async throws -> User {
        let user = User(name: "Olivia Chen", email: "olivia@privaterelay.example")
        self.user = user
        return user
    }

    public func update(_ user: User) async throws -> User {
        self.user = user
        return user
    }

    public func signOut() async {
        user = nil
    }

    public func deleteAccount() async throws {
        user = nil
    }
}

// MARK: - Time

/// A clock whose `sleep` returns immediately — debounce / retry logic tested without waiting.
public struct ImmediateClock: Clock {
    public typealias Duration = Swift.Duration

    public struct Instant: InstantProtocol {
        public var offset: Swift.Duration
        public func advanced(by duration: Swift.Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Swift.Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    public init() {}

    public var now: Instant {
        Instant(offset: .zero)
    }

    public var minimumResolution: Swift.Duration {
        .zero
    }

    public func sleep(until _: Instant, tolerance _: Swift.Duration?) async throws {
        try Task.checkCancellation()
    }
}
