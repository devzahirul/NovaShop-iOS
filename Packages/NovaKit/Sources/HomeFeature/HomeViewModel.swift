import Domain
import Foundation
import NovaCore
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public struct Content: Equatable, Sendable {
        public let hero: EditorialCollection?
        public let featured: EditorialCollection?
        public let categories: [ProductCategory]
        public let newArrivals: [Product]
        public let bestSellers: [Product]
    }

    public private(set) var state: LoadState<Content> = .idle
    @ObservationIgnored private let catalog: any CatalogRepository

    /// Init does no work — views can be re-created freely; loading starts in `.task`.
    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            // Three independent requests run concurrently (structured — cancelled together).
            async let categories = catalog.categories()
            async let products = catalog.products()
            async let collections = catalog.collections()
            let (loadedCategories, loadedProducts, loadedCollections) = try await (categories, products, collections)

            state = .loaded(Content(
                hero: loadedCollections.first,
                featured: loadedCollections.dropFirst().first,
                categories: loadedCategories,
                newArrivals: ProductFilterEngine.sort(loadedProducts.filter(\.isNew), by: .newest),
                bestSellers: Array(ProductFilterEngine.sort(loadedProducts, by: .bestSelling).prefix(6))
            ))
        } catch is CancellationError {
            // View disappeared; keep whatever we had.
        } catch {
            if state.value == nil {
                state = .failed(error.userFacing)
            }
        }
    }
}
