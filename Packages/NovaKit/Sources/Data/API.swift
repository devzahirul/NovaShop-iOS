import Domain
import Foundation
import Networking

/// The API surface, declared once. Features never see paths or DTOs.
enum API {
    static var catalog: Endpoint<CatalogDTO> {
        Endpoint(path: "v1/catalog")
    }

    static func reviews(productID: Product.ID) -> Endpoint<ReviewPageDTO> {
        Endpoint(path: "v1/products/\(productID.rawValue)/reviews")
    }

    static var notifications: Endpoint<[NotificationDTO]> {
        Endpoint(path: "v1/notifications")
    }
}
