import Foundation

public enum SortOption: String, CaseIterable, Identifiable, Sendable, Codable {
    case featured, newest, bestSelling, priceLowToHigh, priceHighToLow, rating

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .featured: "Featured"
        case .newest: "New Arrivals"
        case .bestSelling: "Best Selling"
        case .priceLowToHigh: "Price: Low to High"
        case .priceHighToLow: "Price: High to Low"
        case .rating: "Highest Rated"
        }
    }
}

/// A complete, value-typed description of "what products should this screen show".
/// Being `Hashable` it doubles as a navigation route payload and a `.task(id:)` key.
public struct ProductQuery: Hashable, Sendable, Codable {
    public var text: String
    public var categoryIDs: Set<ProductCategory.ID>
    public var styles: Set<String>
    public var sizes: Set<Size>
    public var colorNames: Set<String>
    public var priceRange: ClosedRange<Decimal>?
    public var onSaleOnly: Bool
    public var inStockOnly: Bool
    public var tag: String?
    public var sort: SortOption

    public init(
        text: String = "", categoryIDs: Set<ProductCategory.ID> = [], styles: Set<String> = [], sizes: Set<Size> = [],
        colorNames: Set<String> = [], priceRange: ClosedRange<Decimal>? = nil, onSaleOnly: Bool = false,
        inStockOnly: Bool = false, tag: String? = nil, sort: SortOption = .featured
    ) {
        self.text = text
        self.categoryIDs = categoryIDs
        self.styles = styles
        self.sizes = sizes
        self.colorNames = colorNames
        self.priceRange = priceRange
        self.onSaleOnly = onSaleOnly
        self.inStockOnly = inStockOnly
        self.tag = tag
        self.sort = sort
    }

    /// Number of refinements applied from the filter sheet (drives the "Filter (3)" badge).
    public var activeFilterCount: Int {
        [
            !categoryIDs.isEmpty, !sizes.isEmpty, !colorNames.isEmpty,
            priceRange != nil, onSaleOnly, inStockOnly,
        ].count(where: { $0 })
    }

    /// Clears filter-sheet refinements while keeping the search text, scope and sort.
    public func resettingFilters() -> ProductQuery {
        ProductQuery(text: text, styles: styles, tag: tag, sort: sort)
    }
}

/// Pure, synchronous filtering + ranking. Lives in Domain so it is unit-tested once and reused by
/// the repository (server-side in production) and the filter sheet's live "Apply (N)" counter.
public enum ProductFilterEngine {
    public static func apply(_ query: ProductQuery, to products: [Product]) -> [Product] {
        let tokens = query.text
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let filtered = products.filter { product in
            if !query.categoryIDs.isEmpty, !query.categoryIDs.contains(product.categoryID) {
                return false
            }
            if !query.styles.isEmpty, !query.styles.contains(product.style) {
                return false
            }
            if !query.sizes.isEmpty, query.sizes.isDisjoint(with: product.sizes) {
                return false
            }
            if !query.colorNames.isEmpty, !product.colors.contains(where: { query.colorNames.contains($0.name) }) {
                return false
            }
            if let range = query.priceRange, !range.contains(product.price) {
                return false
            }
            if query.onSaleOnly, !product.isOnSale {
                return false
            }
            if query.inStockOnly, !product.inStock {
                return false
            }
            if let tag = query.tag, !product.tags.contains(tag) {
                return false
            }
            if !tokens.isEmpty {
                let haystack = searchableText(for: product)
                return tokens.allSatisfy { haystack.contains($0) }
            }
            return true
        }
        return sort(filtered, by: query.sort)
    }

    public static func sort(_ products: [Product], by option: SortOption) -> [Product] {
        switch option {
        case .featured:
            products // Server order is the merchandised order.
        case .newest:
            products.sorted { $0.releasedAt > $1.releasedAt }
        case .bestSelling:
            products.sorted { $0.popularity > $1.popularity }
        case .priceLowToHigh:
            products.sorted { ($0.price, $0.name) < ($1.price, $1.name) }
        case .priceHighToLow:
            products.sorted { ($0.price, $1.name) > ($1.price, $0.name) }
        case .rating:
            products.sorted { ($0.rating, $0.reviewCount) > ($1.rating, $1.reviewCount) }
        }
    }

    private static func searchableText(for product: Product) -> String {
        ([product.name, product.brand, product.style, product.categoryID.rawValue] + product.colors.map(\.name))
            .joined(separator: " ")
            .lowercased()
    }

    /// Price bounds of a catalog, used to seed the price slider.
    public static func priceBounds(of products: [Product]) -> ClosedRange<Decimal> {
        let prices = products.map(\.price)
        guard let lower = prices.min(), let upper = prices.max() else { return 0 ... 0 }
        return lower ... upper
    }
}
