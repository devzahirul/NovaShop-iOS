import Foundation

public struct Product: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Tagged<Product, String>

    public let id: ID
    public let name: String
    public let brand: String
    public let price: Decimal
    /// Original price when the item is discounted.
    public let compareAtPrice: Decimal?
    public let categoryID: ProductCategory.ID
    /// Sub-type used by the category chips (Maxi, Midi, Mini, Formal…).
    public let style: String
    public let imageURLs: [URL]
    public let colors: [ProductColor]
    public let sizes: [Size]
    public let rating: Double
    public let reviewCount: Int
    public let summary: String
    public let details: [String]
    public let tags: Set<String>
    public let inStock: Bool
    public let releasedAt: Date
    /// Units sold in the last 30 days — drives "Best Selling".
    public let popularity: Int

    public init(
        id: ID, name: String, brand: String = "NovaShop", price: Decimal, compareAtPrice: Decimal? = nil,
        categoryID: ProductCategory.ID, style: String = "", imageURLs: [URL], colors: [ProductColor], sizes: [Size],
        rating: Double, reviewCount: Int, summary: String = "", details: [String] = [], tags: Set<String> = [],
        inStock: Bool = true, releasedAt: Date = .distantPast, popularity: Int = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.price = price
        self.compareAtPrice = compareAtPrice
        self.categoryID = categoryID
        self.style = style
        self.imageURLs = imageURLs
        self.colors = colors
        self.sizes = sizes
        self.rating = rating
        self.reviewCount = reviewCount
        self.summary = summary
        self.details = details
        self.tags = tags
        self.inStock = inStock
        self.releasedAt = releasedAt
        self.popularity = popularity
    }

    public var isOnSale: Bool {
        guard let compareAtPrice else { return false }
        return compareAtPrice > price
    }

    public var isNew: Bool {
        tags.contains(ProductTag.new)
    }

    public var primaryImageURL: URL? {
        imageURLs.first
    }
}

public enum ProductTag {
    public static let new = "new"
    public static let linenEdit = "linen-edit"
    public static let bestSeller = "best-seller"
}

public struct ProductColor: Identifiable, Hashable, Sendable, Codable {
    public var id: String {
        name
    }

    public let name: String
    /// sRGB hex, e.g. `#C9A98C`.
    public let hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum Size: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case xs = "XS", small = "S", medium = "M", large = "L", xl = "XL", oneSize = "One Size"

    public var id: String {
        rawValue
    }

    public static func < (lhs: Size, rhs: Size) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public struct ProductCategory: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Tagged<ProductCategory, String>

    public let id: ID
    public let name: String
    public let imageURL: URL
    /// Chips shown on the category screen (e.g. Maxi, Midi, Mini, Formal).
    public let styles: [String]

    public init(id: ID, name: String, imageURL: URL, styles: [String] = []) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.styles = styles
    }
}

public struct EditorialCollection: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Tagged<EditorialCollection, String>

    public let id: ID
    public let eyebrow: String
    public let title: String
    public let subtitle: String
    public let ctaTitle: String
    public let heroImageURL: URL
    public let editorialImageURLs: [URL]
    public let storyTitle: String
    public let storyBody: String
    /// Products carrying this tag belong to the collection.
    public let productTag: String

    public init(
        id: ID, eyebrow: String, title: String, subtitle: String, ctaTitle: String, heroImageURL: URL,
        editorialImageURLs: [URL], storyTitle: String, storyBody: String, productTag: String
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.ctaTitle = ctaTitle
        self.heroImageURL = heroImageURL
        self.editorialImageURLs = editorialImageURLs
        self.storyTitle = storyTitle
        self.storyBody = storyBody
        self.productTag = productTag
    }
}
