import Domain
import Foundation

// Wire models. Kept separate from Domain so API changes (renamed keys, cents vs. decimals,
// nullable fields) are absorbed here and never ripple into features.

public struct CatalogDTO: Decodable, Sendable {
    let categories: [CategoryDTO]
    let products: [ProductDTO]
    let collections: [CollectionDTO]
    let popularSearches: [String]
}

struct CategoryDTO: Decodable, Sendable {
    let id: String
    let name: String
    let image: URL
    let styles: [String]

    func toDomain() -> ProductCategory {
        ProductCategory(id: .init(id), name: name, imageURL: image, styles: styles)
    }
}

struct ProductDTO: Decodable, Sendable {
    struct ColorDTO: Decodable, Sendable {
        let name: String
        let hex: String
    }

    let id: String
    let name: String
    let brand: String
    let priceCents: Int
    let compareAtCents: Int?
    let categoryId: String
    let style: String
    let images: [URL]
    let colors: [ColorDTO]
    let sizes: [String]
    let rating: Double
    let reviewCount: Int
    let summary: String
    let details: [String]
    let tags: [String]
    let inStock: Bool
    let releasedAt: Date
    let popularity: Int

    func toDomain() -> Product {
        Product(
            id: .init(id),
            name: name,
            brand: brand,
            price: Decimal(priceCents) / 100,
            compareAtPrice: compareAtCents.map { Decimal($0) / 100 },
            categoryID: .init(categoryId),
            style: style,
            imageURLs: images,
            colors: colors.map { ProductColor(name: $0.name, hex: $0.hex) },
            // Unknown sizes from a newer API version are dropped, not crashed on.
            sizes: sizes.compactMap(Size.init(rawValue:)),
            rating: rating,
            reviewCount: reviewCount,
            summary: summary,
            details: details,
            tags: Set(tags),
            inStock: inStock,
            releasedAt: releasedAt,
            popularity: popularity
        )
    }
}

struct CollectionDTO: Decodable, Sendable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let ctaTitle: String
    let heroImage: URL
    let editorialImages: [URL]
    let storyTitle: String
    let storyBody: String
    let productTag: String

    func toDomain() -> EditorialCollection {
        EditorialCollection(
            id: .init(id), eyebrow: eyebrow, title: title, subtitle: subtitle, ctaTitle: ctaTitle,
            heroImageURL: heroImage, editorialImageURLs: editorialImages, storyTitle: storyTitle,
            storyBody: storyBody, productTag: productTag
        )
    }
}

public struct ReviewPageDTO: Decodable, Sendable {
    struct SummaryDTO: Decodable, Sendable {
        let average: Double
        let total: Int
        let distribution: [String: Double]
    }

    struct ReviewDTO: Decodable, Sendable {
        let id: String
        let productId: String
        let author: String
        let rating: Int
        let body: String
        let date: Date
        let isVerified: Bool
        let photoUrls: [URL]
    }

    let summary: SummaryDTO
    let items: [ReviewDTO]

    func toDomain() -> ReviewPage {
        let distribution = Dictionary(uniqueKeysWithValues: summary.distribution.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        return ReviewPage(
            stats: ReviewStats(average: summary.average, total: summary.total, distribution: distribution),
            reviews: items.map {
                Review(
                    id: $0.id, productID: .init($0.productId), author: $0.author, rating: $0.rating, body: $0.body,
                    date: $0.date, isVerified: $0.isVerified, photoURLs: $0.photoUrls
                )
            }
        )
    }
}

struct NotificationDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let date: Date
    let isRead: Bool

    func toDomain() -> AppNotification {
        AppNotification(
            id: id, kind: AppNotification.Kind(rawValue: kind) ?? .system, title: title, body: body, date: date, isRead: isRead
        )
    }
}
