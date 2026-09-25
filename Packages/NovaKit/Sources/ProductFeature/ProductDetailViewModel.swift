import Domain
import Foundation
import NovaCore
import Observation

@MainActor
@Observable
public final class ProductDetailViewModel {
    public enum AddToCartResult: Equatable {
        case added
        case needsSize
    }

    public private(set) var product: LoadState<Product>
    public private(set) var reviews: ReviewPage?
    public private(set) var related: [Product] = []
    public var selectedColor: ProductColor?
    public var selectedSize: Size?
    public private(set) var showSizeError = false

    @ObservationIgnored private let productID: Product.ID
    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private let cart: CartStore
    @ObservationIgnored private let recentlyViewed: RecentlyViewedStore

    /// `preview` (the product the user tapped) renders instantly — no spinner between grid and detail.
    /// Deep links arrive without a preview and load by id.
    public init(
        productID: Product.ID,
        preview: Product?,
        catalog: any CatalogRepository,
        cart: CartStore,
        recentlyViewed: RecentlyViewedStore
    ) {
        self.productID = productID
        self.catalog = catalog
        self.cart = cart
        self.recentlyViewed = recentlyViewed
        product = preview.map(LoadState.loaded) ?? .idle
        selectedColor = preview?.colors.first
        selectedSize = Self.defaultSize(for: preview)
    }

    public func load() async {
        if product.value == nil {
            product = .loading
        }
        do {
            let loaded = try await catalog.product(id: productID)
            if product.value == nil {
                selectedColor = loaded.colors.first
                selectedSize = Self.defaultSize(for: loaded)
            }
            product = .loaded(loaded)
            recentlyViewed.record(loaded)

            // Secondary content: loaded concurrently, failures don't break the page.
            async let reviewPage = catalog.reviews(for: productID)
            async let similar = catalog.search(ProductQuery(categoryIDs: [loaded.categoryID], sort: .bestSelling))
            reviews = try? await reviewPage
            related = await ((try? similar) ?? []).filter { $0.id != loaded.id }.prefix(6).map(\.self)
        } catch is CancellationError {
        } catch {
            if product.value == nil {
                product = .failed(error.userFacing)
            }
        }
    }

    public func selectSize(_ size: Size) {
        selectedSize = size
        showSizeError = false
    }

    @discardableResult
    public func addToCart() -> AddToCartResult {
        guard let product = product.value else { return .needsSize }
        guard let selectedSize else {
            showSizeError = true
            return .needsSize
        }
        cart.add(product, color: selectedColor, size: selectedSize)
        return .added
    }

    /// Single-size products (bags, sunglasses) don't make the shopper pick "One Size".
    private static func defaultSize(for product: Product?) -> Size? {
        guard let product, product.sizes.count == 1 else { return nil }
        return product.sizes.first
    }
}

@MainActor
@Observable
public final class ReviewsViewModel {
    public let product: Product
    public private(set) var state: LoadState<ReviewPage> = .idle
    public var filter: ReviewFilter = .all

    @ObservationIgnored private let catalog: any CatalogRepository

    public init(product: Product, catalog: any CatalogRepository) {
        self.product = product
        self.catalog = catalog
    }

    public var visibleReviews: [Review] {
        filter.apply(to: state.value?.reviews ?? [])
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            state = try await .loaded(catalog.reviews(for: product.id))
        } catch is CancellationError {
        } catch {
            state = .failed(error.userFacing)
        }
    }
}
