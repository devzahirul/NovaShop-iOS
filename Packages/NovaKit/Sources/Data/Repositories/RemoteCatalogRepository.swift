import Domain
import Foundation
import Networking
import NovaCore

/// Where catalog data comes from. Fixtures and Supabase expose different endpoints but decode into
/// the same DTOs, so everything above this line is backend-agnostic.
public protocol CatalogRemoteDataSource: Sendable {
    func fetchCatalog() async throws -> CatalogDTO
    func fetchReviews(productID: Product.ID) async throws -> ReviewPageDTO
}

/// The catalog as persisted on disk for offline browsing / instant launch.
public struct CatalogSnapshot: Codable, Sendable {
    let categories: [ProductCategory]
    let products: [Product]
    let collections: [EditorialCollection]
    let popularSearches: [String]
    let fetchedAt: Date

    var productsByID: [Product.ID: Product] {
        Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Catalog repository: in-memory single-flight cache + on-disk snapshot, stale-while-revalidate.
///
/// - First read of a session with a disk snapshot → returned **immediately** (no spinner, works
///   offline) while a background refresh fetches fresh data.
/// - Concurrent readers share one in-flight request (Home, Shop and Search all load at launch).
/// - Network failure with any snapshot available → serve the snapshot instead of an error;
///   failures are throttled so an offline session doesn't hammer a dead network.
public actor RemoteCatalogRepository: CatalogRepository {
    private let source: any CatalogRemoteDataSource
    private let diskCache: (any Persisting<CatalogSnapshot>)?
    private let cacheLifetime: Duration
    private let failureCooldown: Duration
    private let clock = ContinuousClock()

    private var snapshot: CatalogSnapshot?
    private var productsByID: [Product.ID: Product] = [:]
    private var fetchedAt: ContinuousClock.Instant?
    private var lastFailure: ContinuousClock.Instant?
    private var inFlight: Task<CatalogSnapshot, any Error>?
    private var didReadDisk = false
    private var reviewCache: [Product.ID: ReviewPage] = [:]

    public init(
        source: any CatalogRemoteDataSource,
        diskCache: (any Persisting<CatalogSnapshot>)? = nil,
        cacheLifetime: Duration = .seconds(300),
        failureCooldown: Duration = .seconds(10)
    ) {
        self.source = source
        self.diskCache = diskCache
        self.cacheLifetime = cacheLifetime
        self.failureCooldown = failureCooldown
    }

    /// Fixture-backed convenience (the portfolio's offline demo mode).
    public init(client: APIClient, cacheLifetime: Duration = .seconds(300)) {
        self.init(source: FixtureCatalogSource(client: client), cacheLifetime: cacheLifetime)
    }

    public func categories() async throws -> [ProductCategory] {
        try await load().categories
    }

    public func products() async throws -> [Product] {
        try await load().products
    }

    public func product(id: Product.ID) async throws -> Product {
        _ = try await load()
        guard let product = productsByID[id] else { throw APIError.http(status: 404) }
        return product
    }

    public func search(_ query: ProductQuery) async throws -> [Product] {
        let products = try await load().products
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
        let page = try await source.fetchReviews(productID: productID).toDomain()
        reviewCache[productID] = page
        return page
    }

    // MARK: Cache

    private func load() async throws -> CatalogSnapshot {
        if let snapshot, let fetchedAt, fetchedAt.duration(to: clock.now) < cacheLifetime {
            return snapshot
        }
        if !didReadDisk {
            didReadDisk = true
            if snapshot == nil, let disk = await diskCache?.load() {
                apply(disk, fresh: false)
                startRefresh() // revalidate in the background; callers get the cached copy now
                return disk
            }
        }
        if let snapshot, let lastFailure, lastFailure.duration(to: clock.now) < failureCooldown {
            return snapshot // recently failed (offline?) — don't retry on every screen appearance
        }
        do {
            return try await startRefresh().value
        } catch {
            if let snapshot {
                return snapshot
            }
            throw error
        }
    }

    @discardableResult
    private func startRefresh() -> Task<CatalogSnapshot, any Error> {
        if let inFlight {
            return inFlight
        }
        let source = source
        let task = Task<CatalogSnapshot, any Error> {
            try await Perf.measure("Catalog.Fetch") {
                let dto = try await source.fetchCatalog()
                return CatalogSnapshot(
                    categories: dto.categories.map { $0.toDomain() },
                    products: dto.products.map { $0.toDomain() },
                    collections: dto.collections.map { $0.toDomain() },
                    popularSearches: dto.popularSearches,
                    fetchedAt: .now
                )
            }
        }
        inFlight = task
        Task { await self.finish(task) }
        return task
    }

    private func finish(_ task: Task<CatalogSnapshot, any Error>) async {
        defer { inFlight = nil }
        do {
            let fresh = try await task.value
            apply(fresh, fresh: true)
            lastFailure = nil
            try? await diskCache?.save(fresh)
        } catch {
            lastFailure = clock.now
            Log.network.notice("Catalog refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(_ newSnapshot: CatalogSnapshot, fresh: Bool) {
        snapshot = newSnapshot
        productsByID = newSnapshot.productsByID
        fetchedAt = fresh ? clock.now : nil
    }
}

/// Bundled fixtures served through the real API client.
public struct FixtureCatalogSource: CatalogRemoteDataSource {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchCatalog() async throws -> CatalogDTO {
        try await client.send(API.catalog)
    }

    public func fetchReviews(productID: Product.ID) async throws -> ReviewPageDTO {
        try await client.send(API.reviews(productID: productID))
    }
}
