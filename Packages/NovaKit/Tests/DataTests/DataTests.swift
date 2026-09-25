@testable import Data
import Domain
import Foundation
import Networking
import Testing
import TestSupport

/// Counts requests while delegating to the fixture transport.
final class CountingTransport: HTTPTransport, @unchecked Sendable {
    private let inner = FixtureTransport(latency: .milliseconds(50))
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { count += 1 }
        return try await inner.send(request)
    }
}

@Suite("Fixture API contract")
struct FixtureContractTests {
    let client = APIClient(baseURL: URL(string: "https://api.novashop.example")!, transport: FixtureTransport(latency: .zero))

    @Test("Catalog fixtures decode through the production DTO pipeline")
    func catalogDecodes() async throws {
        let repository = RemoteCatalogRepository(client: client)
        let products = try await repository.products()
        let categories = try await repository.categories()
        #expect(products.count >= 20)
        #expect(categories.map(\.name).contains("Dresses"))
        #expect(products.allSatisfy { !$0.imageURLs.isEmpty && !$0.sizes.isEmpty })

        let amelie = try await repository.product(id: "amelie-floral-midi")
        #expect(amelie.price == 129)
        #expect(amelie.reviewCount == 320)
    }

    @Test("Review summary comes from the server aggregate, not the page")
    func reviews() async throws {
        let page = try await RemoteCatalogRepository(client: client).reviews(for: "amelie-floral-midi")
        #expect(page.stats.total == 320)
        #expect(page.stats.average == 4.8)
        #expect(page.stats.distribution[5] == 0.72)
        #expect(!page.reviews.isEmpty)
    }

    @Test("Unknown product returns 404")
    func unknownProduct() async {
        await #expect(throws: APIError.http(status: 404)) {
            try await RemoteCatalogRepository(client: client).product(id: "nope")
        }
    }
}

@Suite("RemoteCatalogRepository caching")
struct CatalogCachingTests {
    @Test("Concurrent callers share one in-flight request (single-flight)")
    func coalescesConcurrentRequests() async throws {
        let transport = CountingTransport()
        let repository = try RemoteCatalogRepository(client: APIClient(
            baseURL: #require(URL(string: "https://x.example")),
            transport: transport
        ))

        async let products = repository.products()
        async let categories = repository.categories()
        async let collections = repository.collections()
        async let search = repository.search(ProductQuery(text: "linen"))
        _ = try await (products, categories, collections, search)

        #expect(transport.requestCount == 1)
        _ = try await repository.products()
        #expect(transport.requestCount == 1, "Served from cache within its lifetime")
    }
}

@Suite("Persistence")
struct PersistenceTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test("FileStore round-trips Codable values")
    func roundTrip() async throws {
        let directory = temporaryDirectory()
        let store = FileStore<[CartItem]>(filename: "cart", directory: directory)
        #expect(await store.load() == nil)
        let items = [CartItem(product: .fixture(), color: nil, size: .medium, quantity: 2)]
        try await store.save(items)
        #expect(await FileStore<[CartItem]>(filename: "cart", directory: directory).load() == items)
    }

    @Test("Corrupt files are discarded instead of crashing")
    func corruptFile() async throws {
        let directory = temporaryDirectory().appending(path: "NovaShop")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "cart.json"))
        let store = FileStore<[CartItem]>(filename: "cart", directory: directory.deletingLastPathComponent())
        #expect(await store.load() == nil)
    }
}

@Suite("Local services")
struct LocalServiceTests {
    @Test("First address becomes default; a new default demotes the old one")
    func defaultAddress() async throws {
        let repository = LocalProfileRepository(addressStore: InMemoryPersistence(), paymentStore: InMemoryPersistence())
        var first = Address.fixture(isDefault: false)
        first = try await repository.save(first)[0]
        #expect(first.isDefault)
        let all = try await repository.save(Address(
            fullName: "B",
            line1: "1",
            city: "NY",
            state: "NY",
            postalCode: "10001",
            isDefault: true
        ))
        #expect(all.filter(\.isDefault).count == 1)
        #expect(all.last?.isDefault == true)

        let remaining = try await repository.deleteAddress(id: #require(all.last?.id))
        #expect(remaining.first?.isDefault == true, "Deleting the default promotes another address")
    }

    @Test("Coupon service validates codes and minimums")
    func coupons() async throws {
        let service = LocalCouponService(latency: .zero)
        #expect(try await service.validate(code: " summer20 ", subtotal: 10).code == "SUMMER20")
        await #expect(throws: CouponError.minimumNotMet(150)) { try await service.validate(code: "NOVA25", subtotal: 100) }
        await #expect(throws: CouponError.notFound) { try await service.validate(code: "FAKE", subtotal: 100) }
    }

    @Test("Orders persist and the decline test card fails")
    func orders() async throws {
        let service = LocalOrderService(store: InMemoryPersistence(), processingTime: .zero)
        let items = [CartItem(product: .fixture(price: 100), color: nil, size: .medium)]
        let order = try await service.placeOrder(OrderDraft(
            items: items,
            address: .fixture(),
            payment: .applePay,
            shipping: .express,
            coupon: nil
        ))
        #expect(order.pricing.shipping == 12)
        #expect(try await service.orders().count == 1)

        let declining = PaymentMethod(kind: .card(brand: .visa, last4: "0002", expiry: "12/30", holder: "O"))
        await #expect(throws: PaymentError.declined) {
            try await service.placeOrder(OrderDraft(
                items: items,
                address: .fixture(),
                payment: declining,
                shipping: .standard,
                coupon: nil
            ))
        }
    }

    @Test("Auth: sign up, restore from secure storage, duplicate email, sign out")
    func auth() async throws {
        let storage = EphemeralSecureStorage()
        let service = LocalAuthService(secureStorage: storage, inMemory: true, latency: .zero)
        let user = try await service.signUp(name: "Olivia Chen", email: "olivia@example.com", password: "password123")
        #expect(await service.restoreSession() == user)
        await #expect(throws: AuthError.emailAlreadyInUse) {
            try await service.signUp(name: "O", email: "OLIVIA@example.com", password: "password123")
        }
        await #expect(throws: AuthError.invalidCredentials) {
            try await service.signIn(email: "olivia@example.com", password: "wrong-password")
        }
        await service.signOut()
        #expect(await service.restoreSession() == nil)
    }
}
