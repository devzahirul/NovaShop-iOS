import Foundation
import NovaCore
import Observation

/// Saved items. Keeps an ordered array for display plus a `Set` index so the heart button on every
/// product card answers `contains` in O(1) — it is evaluated for every visible cell on every scroll.
@MainActor
@Observable
public final class WishlistStore {
    public private(set) var products: [Product] = []
    /// Observed too, so `contains` registers a dependency and hearts refresh on toggle.
    private var index: Set<Product.ID> = []
    @ObservationIgnored private let persistence: any Persisting<[Product]>
    @ObservationIgnored private let saveQueue: SaveQueue<[Product]>
    @ObservationIgnored private var isHydrated = false

    public init(persistence: any Persisting<[Product]>) {
        self.persistence = persistence
        saveQueue = SaveQueue(store: persistence)
    }

    public var count: Int {
        products.count
    }

    public func contains(_ id: Product.ID) -> Bool {
        index.contains(id)
    }

    public func hydrate() async {
        guard !isHydrated else { return }
        isHydrated = true
        let stored = await persistence.load() ?? []
        let local = products
        products = local + stored.filter { !index.contains($0.id) }
        index = Set(products.map(\.id))
    }

    public func toggle(_ product: Product) {
        if index.contains(product.id) {
            remove(product.id)
        } else {
            products.insert(product, at: 0)
            index.insert(product.id)
            saveQueue.enqueue(products)
        }
    }

    public func remove(_ id: Product.ID) {
        products.removeAll { $0.id == id }
        index.remove(id)
        saveQueue.enqueue(products)
    }

    public func flush() async {
        await saveQueue.flush()
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
