import Domain
import Foundation
import NovaCore
import Observation

/// Drives every "grid of products for a query" screen: category, collection, search results, see-all.
/// The query is the single source of truth; the view re-runs `load()` via `.task(id: query)`, so a
/// newer query automatically cancels the previous in-flight search.
@MainActor
@Observable
public final class ProductListingViewModel {
    public var query: ProductQuery
    public private(set) var state: LoadState<[Product]> = .idle
    /// Full catalog, used for filter bounds and the filter sheet's live result count.
    public private(set) var catalogProducts: [Product] = []
    public private(set) var categories: [ProductCategory] = []

    @ObservationIgnored private let catalog: any CatalogRepository

    public init(query: ProductQuery, catalog: any CatalogRepository) {
        self.query = query
        self.catalog = catalog
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            async let results = catalog.search(query)
            async let all = catalog.products()
            async let categories = catalog.categories()
            let (loadedResults, loadedAll, loadedCategories) = try await (results, all, categories)
            state = .loaded(loadedResults)
            catalogProducts = loadedAll
            self.categories = loadedCategories
        } catch is CancellationError {
            // Superseded by a newer query.
        } catch {
            state = .failed(error.userFacing)
        }
    }

    public var priceBounds: ClosedRange<Decimal> {
        let bounds = ProductFilterEngine.priceBounds(of: catalogProducts)
        // Round outward to friendly slider stops.
        let lower = (bounds.lowerBound / 10).rounded(.down) * 10
        let upper = max((bounds.upperBound / 10).rounded(.up) * 10, lower + 10)
        return lower ... upper
    }

    /// Live "Apply Filters (N)" count while the user tweaks the sheet — pure and synchronous.
    public func resultCount(for draft: ProductQuery) -> Int {
        ProductFilterEngine.apply(draft, to: catalogProducts).count
    }

    public func setStyle(_ style: String?) {
        query.styles = style.map { [$0] } ?? []
    }
}

extension Decimal {
    func rounded(_ rule: FloatingPointRoundingRule) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, rule == .down ? .down : .up)
        return result
    }
}
