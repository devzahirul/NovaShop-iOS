import Foundation
import NovaCore
import Observation

/// Saved items, local-first and synced like the cart. Membership checks are O(1) (`SyncedList.ids`)
/// because the heart on every visible product card asks on every scroll frame.
@MainActor
@Observable
public final class WishlistStore {
    @ObservationIgnored public let list: SyncedList<Product>

    public init(
        repository: any LocalFirstRepository<Product>,
        debounce: Duration = .milliseconds(600),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        list = SyncedList(repository: repository, debounce: debounce, clock: clock)
    }

    public var products: [Product] {
        list.records
    }

    public var count: Int {
        list.records.count
    }

    public var syncStatus: SyncStatus {
        list.status
    }

    public func contains(_ id: Product.ID) -> Bool {
        list.ids.contains(id)
    }

    public func hydrate() async {
        await list.hydrate()
    }

    public func sync() async {
        await list.sync()
    }

    public func toggle(_ product: Product) {
        if contains(product.id) {
            list.remove(product.id)
        } else {
            list.save(product, insertAtFront: true)
        }
    }

    public func remove(_ id: Product.ID) {
        list.remove(id)
    }

    public func removeAllLocally() async {
        await list.removeAllLocally()
    }

    public func prepareForMerge() async {
        await list.prepareForMerge()
    }

    public func flush() async {
        await list.flushWrites()
    }
}

/// Most-recent-first, de-duplicated, capped history of viewed products.
@MainActor
@Observable
public final class RecentlyViewedStore {
    public private(set) var products: [Product] = []
    @ObservationIgnored private let persistence: any Persisting<[Product]>
    @ObservationIgnored private let saveQueue: SaveQueue<[Product]>
    @ObservationIgnored private var isHydrated = false

    public static let capacity = 20

    public init(persistence: any Persisting<[Product]>) {
        self.persistence = persistence
        saveQueue = SaveQueue(store: persistence)
    }

    public func hydrate() async {
        guard !isHydrated else { return }
        isHydrated = true
        let stored = await persistence.load() ?? []
        let local = products
        products = Array((local + stored.filter { item in !local.contains { $0.id == item.id } }).prefix(Self.capacity))
    }

    public func record(_ product: Product) {
        products.removeAll { $0.id == product.id }
        products.insert(product, at: 0)
        if products.count > Self.capacity {
            products.removeLast(products.count - Self.capacity)
        }
        saveQueue.enqueue(products)
    }

    public func clear() {
        products = []
        saveQueue.enqueue(products)
    }

    public func flush() async {
        await saveQueue.flush()
    }
}

/// Recent search terms (case-insensitive de-dupe, capped).
@MainActor
@Observable
public final class SearchHistoryStore {
    public private(set) var terms: [String] = []
    @ObservationIgnored private let persistence: any Persisting<[String]>
    @ObservationIgnored private let saveQueue: SaveQueue<[String]>
    @ObservationIgnored private var isHydrated = false

    public static let capacity = 8

    public init(persistence: any Persisting<[String]>) {
        self.persistence = persistence
        saveQueue = SaveQueue(store: persistence)
    }

    public func hydrate() async {
        guard !isHydrated else { return }
        isHydrated = true
        terms = await persistence.load() ?? []
    }

    public func record(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        terms.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        terms.insert(trimmed, at: 0)
        terms = Array(terms.prefix(Self.capacity))
        saveQueue.enqueue(terms)
    }

    public func remove(_ term: String) {
        terms.removeAll { $0 == term }
        saveQueue.enqueue(terms)
    }

    public func clear() {
        terms = []
        saveQueue.enqueue(terms)
    }

    public func flush() async {
        await saveQueue.flush()
    }
}
