import Domain
import Foundation
import Networking
import NovaCore

/// Catalog repository with an in-memory, single-flight cache.
///
/// Home, Shop and Search all ask for the catalog at launch. Without coalescing that would be three
/// identical requests; with the `inFlight` task every caller awaits the same request and the
/// decode happens once. Being an `actor` makes the cache race-free without a single lock.
public actor RemoteCatalogRepository: CatalogRepository {
    private struct Snapshot: Sendable {
        let categories: [ProductCategory]
        let products: [Product]
        let productsByID: [Product.ID: Product]
        let collections: [EditorialCollection]
        let popularSearches: [String]
    }

    private let client: APIClient
    private let cacheLifetime: Duration
    private let clock = ContinuousClock()

    private var snapshot: Snapshot?
    private var fetchedAt: ContinuousClock.Instant?
    private var inFlight: Task<Snapshot, any Error>?
    private var reviewCache: [Product.ID: ReviewPage] = [:]

    public init(client: APIClient, cacheLifetime: Duration = .seconds(300)) {
        self.client = client
        self.cacheLifetime = cacheLifetime
    }

    public func categories() async throws -> [ProductCategory] {
        try await load().categories
    }

    public func products() async throws -> [Product] {
        try await load().products
    }

    public func product(id: Product.ID) async throws -> Product {
        guard let product = try await load().productsByID[id] else { throw APIError.http(status: 404) }
        return product
    }

    public func search(_ query: ProductQuery) async throws -> [Product] {
        let products = try await load().products
        // In production this is a server query; filtering here keeps fixtures honest to the contract.
        return Perf.measureSync("Catalog.Search") { ProductFilterEngine.apply(query, to: products) }
    }

    public func collections() async throws -> [EditorialCollection] {
        try await load().collections
    }

    public func popularSearches() async throws -> [String] {
        try await load().popularSearches
    }

    public func reviews(for productID: Product.ID) async throws -> ReviewPage {
        if let cached = reviewCache[productID] {
            return cached
        }
        let page = try await client.send(API.reviews(productID: productID)).toDomain()
        reviewCache[productID] = page
        return page
    }

    // MARK: Cache

    private func load() async throws -> Snapshot {
        if let snapshot, let fetchedAt, fetchedAt.duration(to: clock.now) < cacheLifetime {
            return snapshot
        }
        if let inFlight {
            return try await inFlight.value
        }
        let client = client
        let task = Task<Snapshot, any Error> {
            try await Perf.measure("Catalog.Fetch") {
                let dto = try await client.send(API.catalog)
                let products = dto.products.map { $0.toDomain() }
                return Snapshot(
                    categories: dto.categories.map { $0.toDomain() },
                    products: products,
                    productsByID: Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                    collections: dto.collections.map { $0.toDomain() },
                    popularSearches: dto.popularSearches
                )
            }
        }
        inFlight = task
        defer { inFlight = nil }

        let result = try await task.value
        snapshot = result
        fetchedAt = clock.now
        return result
    }
}
