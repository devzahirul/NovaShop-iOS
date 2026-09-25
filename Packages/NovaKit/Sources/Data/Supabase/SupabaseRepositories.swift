import Domain
import Foundation
import Networking
import NovaCore

// Supabase adapters. Each one is a thin PostgREST client over our own `APIClient` (no SDK), so the
// app's architecture doesn't depend on the backend: swapping Supabase for another REST backend
// means rewriting only this file.

enum PostgREST {
    static func query(_ pairs: (String, String)...) -> [URLQueryItem] {
        pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    /// `in.("a","b")` with PostgREST quoting (values may contain commas, spaces, `|`).
    static func inList(_ values: [String]) -> String {
        let quoted = values
            .map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return "in.(\(quoted.joined(separator: ",")))"
    }

    /// Server-raised exceptions (`raise exception 'out_of_stock'`) arrive as `{code: "P0001", message: "out_of_stock"}`.
    static func exception(_ error: any Error) -> (name: String, detail: String?)? {
        guard case let .server(server)? = error as? APIError, let message = server.message else { return nil }
        return (message, server.detail)
    }
}

// MARK: - Catalog

public struct SupabaseCatalogSource: CatalogRemoteDataSource {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func fetchCatalog() async throws -> CatalogDTO {
        struct SearchTerm: Decodable, Sendable { let term: String }
        let ordered = PostgREST.query(("select", "*"), ("order", "sort_order.asc"))
        // Four independent reads in parallel.
        async let categories = client.send(Endpoint<[CategoryDTO]>(path: "rest/v1/categories", queryItems: ordered))
        async let products = client.send(Endpoint<[ProductDTO]>(path: "rest/v1/products", queryItems: ordered))
        async let collections = client.send(Endpoint<[CollectionDTO]>(path: "rest/v1/collections", queryItems: ordered))
        async let searches = client.send(Endpoint<[SearchTerm]>(path: "rest/v1/popular_searches", queryItems: ordered))
        return try await CatalogDTO(
            categories: categories, products: products, collections: collections, popularSearches: searches.map(\.term)
        )
    }

    public func fetchReviews(productID: Product.ID) async throws -> ReviewPageDTO {
        try await client.send(Endpoint<ReviewPageDTO>(
            path: "rest/v1/rpc/product_reviews",
            queryItems: PostgREST.query(("p_product_id", productID.rawValue))
        ))
    }
}

// MARK: - Cart & wishlist remotes (local-first sync targets)

/// Resolves the signed-in user's id for writes (RLS also enforces it server-side).
public typealias CurrentUserID = @Sendable () async -> UUID?

public struct SupabaseCartRemote: RemoteCollection {
    private let client: APIClient
    private let userID: CurrentUserID

    public init(client: APIClient, userID: @escaping CurrentUserID) {
        self.client = client
        self.userID = userID
    }

    public func fetchAll() async throws -> [CartItem] {
        struct Row: Decodable, Sendable {
            let lineKey: String
            let quantity: Int
            let colorName: String?
            let size: String?
            let product: ProductDTO
        }
        let rows = try await client.send(Endpoint<[Row]>(
            path: "rest/v1/cart_items",
            queryItems: PostgREST.query(
                ("select", "line_key,quantity,color_name,size,product:products(*)"),
                ("order", "updated_at.asc")
            )
        ))
        return rows.map { row in
            let product = row.product.toDomain()
            let color = row.colorName.map { name in product.colors.first { $0.name == name } ?? ProductColor(name: name, hex: "#999999") }
            return CartItem(product: product, color: color, size: row.size.flatMap(Size.init(rawValue:)), quantity: row.quantity)
        }
    }

    public func upsert(_ items: [CartItem]) async throws {
        struct Row: Encodable {
            let userId: UUID
            let lineKey: String
            let productId: String
            let colorName: String?
            let size: String?
            let quantity: Int
        }
        guard let user = await userID() else { throw APIError.unauthorized }
        let rows = items.map {
            Row(
                userId: user,
                lineKey: $0.id,
                productId: $0.product.id.rawValue,
                colorName: $0.color?.name,
                size: $0.size?.rawValue,
                quantity: $0.quantity
            )
        }
        _ = try await client.send(Endpoint<EmptyResponse>.json(
            path: "rest/v1/cart_items",
            method: .post,
            body: rows,
            queryItems: PostgREST.query(("on_conflict", "user_id,line_key")),
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
            isRetrySafe: true // absolute quantities → replaying is harmless
        ))
    }

    public func delete(_ ids: [CartItem.ID]) async throws {
        _ = try await client.send(Endpoint<EmptyResponse>(
            path: "rest/v1/cart_items",
            method: .delete,
            queryItems: PostgREST.query(("line_key", PostgREST.inList(ids))),
            headers: ["Prefer": "return=minimal"]
        ))
    }
}

public struct SupabaseWishlistRemote: RemoteCollection {
    private let client: APIClient
    private let userID: CurrentUserID

    public init(client: APIClient, userID: @escaping CurrentUserID) {
        self.client = client
        self.userID = userID
    }

    public func fetchAll() async throws -> [Product] {
        struct Row: Decodable, Sendable { let product: ProductDTO }
        return try await client.send(Endpoint<[Row]>(
            path: "rest/v1/wishlist_items",
            queryItems: PostgREST.query(("select", "product:products(*)"), ("order", "created_at.desc"))
        )).map { $0.product.toDomain() }
    }

    public func upsert(_ products: [Product]) async throws {
        struct Row: Encodable {
            let userId: UUID
            let productId: String
        }
        guard let user = await userID() else { throw APIError.unauthorized }
        _ = try await client.send(Endpoint<EmptyResponse>.json(
            path: "rest/v1/wishlist_items",
            method: .post,
            body: products.map { Row(userId: user, productId: $0.id.rawValue) },
            queryItems: PostgREST.query(("on_conflict", "user_id,product_id")),
            headers: ["Prefer": "resolution=ignore-duplicates,return=minimal"],
            isRetrySafe: true
        ))
    }

    public func delete(_ ids: [Product.ID]) async throws {
        _ = try await client.send(Endpoint<EmptyResponse>(
            path: "rest/v1/wishlist_items",
            method: .delete,
            queryItems: PostgREST.query(("product_id", PostgREST.inList(ids.map(\.rawValue)))),
            headers: ["Prefer": "return=minimal"]
        ))
    }
}

// MARK: - Profile (addresses, cards) — network-first with an offline read cache

public actor SupabaseProfileRepository: ProfileRepository {
    private let client: APIClient
    private let userID: CurrentUserID
    private let addressCache: any Persisting<[Address]>
    private let paymentCache: any Persisting<[PaymentMethod]>

    public init(client: APIClient, userID: @escaping CurrentUserID, cacheDirectory: URL? = nil, inMemory: Bool = false) {
        self.client = client
        self.userID = userID
        addressCache = inMemory ? InMemoryStore<[Address]>() : FileStore<[Address]>(filename: "addresses-cache", directory: cacheDirectory)
        paymentCache = inMemory ? InMemoryStore<[PaymentMethod]>() : FileStore<[PaymentMethod]>(
            filename: "payments-cache",
            directory: cacheDirectory
        )
    }

    public func addresses() async throws -> [Address] {
        do {
            let rows = try await client.send(Endpoint<[AddressDTO]>(
                path: "rest/v1/addresses",
                queryItems: PostgREST.query(("select", "*"), ("order", "created_at.asc"))
            ))
            let addresses = rows.map { $0.toDomain() }
            try? await addressCache.save(addresses)
            return addresses
        } catch let error as APIError where error.isTransient {
            if let cached = await addressCache.load() {
                return cached
            } // offline: last known
            throw error
        }
    }

    public func save(_ address: Address) async throws -> [Address] {
        guard let user = await userID() else { throw APIError.unauthorized }
        _ = try await client.send(Endpoint<EmptyResponse>.json(
            path: "rest/v1/addresses",
            method: .post,
            body: AddressDTO(address, userID: user),
            queryItems: PostgREST.query(("on_conflict", "id")),
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
            isRetrySafe: true // client-generated id → idempotent
        ))
        return try await addresses()
    }

    public func deleteAddress(id: Address.ID) async throws -> [Address] {
        _ = try await client.send(Endpoint<EmptyResponse>(
            path: "rest/v1/addresses",
            method: .delete,
            queryItems: PostgREST.query(("id", "eq.\(id.uuidString.lowercased())")),
            headers: ["Prefer": "return=minimal"]
        ))
        return try await addresses()
    }

    public func paymentMethods() async throws -> [PaymentMethod] {
        do {
            let rows = try await client.send(Endpoint<[PaymentMethodDTO]>(
                path: "rest/v1/payment_methods",
                queryItems: PostgREST.query(("select", "*"), ("order", "created_at.desc"))
            ))
            let methods = rows.map { $0.toDomain() }
            try? await paymentCache.save(methods)
            return methods
        } catch let error as APIError where error.isTransient {
            if let cached = await paymentCache.load() {
                return cached
            }
            throw error
        }
    }

    public func save(_ method: PaymentMethod) async throws -> [PaymentMethod] {
        guard case let .card(brand, last4, expiry, holder) = method.kind else { return try await paymentMethods() }
        guard let user = await userID() else { throw APIError.unauthorized }
        struct Row: Encodable {
            let id: UUID
            let userId: UUID
            let brand: String
            let last4: String
            let expiry: String
            let holder: String
        }
        _ = try await client.send(Endpoint<EmptyResponse>.json(
            path: "rest/v1/payment_methods",
            method: .post,
            body: Row(id: method.id, userId: user, brand: brand.rawValue, last4: last4, expiry: expiry, holder: holder),
            queryItems: PostgREST.query(("on_conflict", "id")),
            headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
            isRetrySafe: true
        ))
        return try await paymentMethods()
    }
}

// MARK: - Checkout & orders (server-authoritative)

public struct SupabaseOrderService: OrderService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func placeOrder(_ draft: OrderDraft) async throws -> Order {
        struct Body: Encodable {
            let pAddressId: UUID
            let pShipping: String
            let pPayment: PaymentDTO
            let pIdempotencyKey: UUID
            let pCoupon: String?
        }
        let endpoint = try Endpoint<OrderDTO>.json(
            path: "rest/v1/rpc/place_order",
            method: .post,
            body: Body(
                pAddressId: draft.address.id,
                pShipping: draft.shipping.rawValue,
                pPayment: PaymentDTO(draft.payment),
                pIdempotencyKey: draft.idempotencyKey,
                pCoupon: draft.coupon?.code
            ),
            timeout: 30,
            // Safe to resend: the idempotency key makes the server return the first order.
            isRetrySafe: true
        )
        do {
            return try await client.send(endpoint).toDomain()
        } catch {
            throw Self.map(error)
        }
    }

    public func orders() async throws -> [Order] {
        try await client.send(Endpoint<[OrderDTO]>(path: "rest/v1/rpc/my_orders")).map { $0.toDomain() }
    }

    static func map(_ error: any Error) -> any Error {
        if case .offline? = error as? APIError {
            return CheckoutError.offline
        }
        guard let exception = PostgREST.exception(error) else { return error }
        switch exception.name {
        case "out_of_stock": return CheckoutError.outOfStock(products: exception.detail ?? "An item")
        case "cart_empty": return CheckoutError.cartEmpty
        case "address_not_found": return CheckoutError.addressNotFound
        case "payment_declined": return PaymentError.declined
        case "coupon_not_found": return CouponError.notFound
        case "coupon_minimum_not_met": return CouponError.minimumNotMet(Decimal(Int(exception.detail ?? "") ?? 0) / 100)
        default: return error
        }
    }
}

extension Endpoint {
    static func json(
        path: String, method: HTTPMethod, body: some Encodable, timeout: TimeInterval, isRetrySafe: Bool
    ) throws -> Endpoint {
        var endpoint = try Endpoint.json(path: path, method: method, body: body, isRetrySafe: isRetrySafe)
        endpoint.timeout = timeout
        return endpoint
    }
}

public struct SupabaseCouponService: CouponService {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func validate(code: String, subtotal: Decimal) async throws -> Coupon {
        struct CouponDTO: Decodable, Sendable {
            let code: String
            let kind: String
            let value: Decimal
            let minimumCents: Int
        }
        let cents = NSDecimalNumber(decimal: subtotal * 100).intValue
        do {
            let dto = try await client.send(Endpoint<CouponDTO>(
                path: "rest/v1/rpc/validate_coupon",
                queryItems: PostgREST.query(("p_code", code.trimmingCharacters(in: .whitespaces)), ("p_subtotal_cents", String(cents)))
            ))
            return Coupon(
                code: dto.code,
                kind: dto.kind == "percentage" ? .percentage(dto.value) : .fixedAmount(dto.value),
                minimumSubtotal: Decimal(dto.minimumCents) / 100
            )
        } catch {
            throw SupabaseOrderService.map(error)
        }
    }
}

public struct SupabaseNotificationRepository: NotificationRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func notifications() async throws -> [AppNotification] {
        try await client.send(Endpoint<[NotificationDTO]>(
            path: "rest/v1/notifications",
            queryItems: PostgREST.query(("select", "id,kind,title,body,date:created_at,is_read"), ("order", "created_at.desc"))
        )).map { $0.toDomain() }
    }
}

// MARK: - DTOs

struct AddressDTO: Codable, Sendable {
    let id: UUID
    var userId: UUID?
    let fullName: String
    let line1: String
    let line2: String
    let city: String
    let state: String
    let postalCode: String
    let country: String
    let isDefault: Bool

    init(_ address: Address, userID: UUID) {
        id = address.id
        userId = userID
        fullName = address.fullName
        line1 = address.line1
        line2 = address.line2
        city = address.city
        state = address.state
        postalCode = address.postalCode
        country = address.country
        isDefault = address.isDefault
    }

    func toDomain() -> Address {
        Address(
            id: id, fullName: fullName, line1: line1, line2: line2, city: city, state: state,
            postalCode: postalCode, country: country, isDefault: isDefault
        )
    }
}

struct PaymentMethodDTO: Decodable, Sendable {
    let id: UUID
    let brand: String
    let last4: String
    let expiry: String
    let holder: String

    func toDomain() -> PaymentMethod {
        PaymentMethod(id: id, kind: .card(brand: CardBrand(rawValue: brand) ?? .unknown, last4: last4, expiry: expiry, holder: holder))
    }
}

struct PaymentDTO: Codable, Sendable {
    let id: String?
    let kind: String
    let brand: String?
    let last4: String?
    let expiry: String?
    let holder: String?

    init(_ method: PaymentMethod) {
        id = method.id.uuidString
        switch method.kind {
        case let .card(brand, last4, expiry, holder):
            kind = "card"
            self.brand = brand.rawValue
            self.last4 = last4
            self.expiry = expiry
            self.holder = holder
        case .applePay:
            kind = "apple_pay"
            brand = nil
            last4 = nil
            expiry = nil
            holder = nil
        case .payPal:
            kind = "paypal"
            brand = nil
            last4 = nil
            expiry = nil
            holder = nil
        }
    }

    func toDomain() -> PaymentMethod {
        let identifier = id.flatMap(UUID.init(uuidString:)) ?? UUID()
        switch kind {
        case "apple_pay": return PaymentMethod(id: identifier, kind: .applePay)
        case "paypal": return PaymentMethod(id: identifier, kind: .payPal)
        default:
            return PaymentMethod(id: identifier, kind: .card(
                brand: CardBrand(rawValue: brand ?? "") ?? .unknown, last4: last4 ?? "", expiry: expiry ?? "", holder: holder ?? ""
            ))
        }
    }
}

struct OrderDTO: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let productId: String
        let name: String
        let imageUrl: URL?
        let colorName: String?
        let colorHex: String?
        let size: String?
        let quantity: Int
        let unitPriceCents: Int
    }

    let id: UUID
    let number: String
    let status: String
    let shippingOption: String
    let shippingAddress: AddressDTO
    let payment: PaymentDTO
    let subtotalCents: Int
    let discountCents: Int
    let shippingCents: Int
    let taxCents: Int
    let totalCents: Int
    let placedAt: Date
    let items: [Item]

    func toDomain() -> Order {
        let lines = items.map { item in
            // An order line is a *snapshot*; it renders without the live catalog.
            let product = Product(
                id: .init(item.productId), name: item.name, price: Decimal(item.unitPriceCents) / 100, categoryID: "",
                imageURLs: item.imageUrl.map { [$0] } ?? [], colors: [], sizes: [], rating: 0, reviewCount: 0
            )
            return CartItem(
                product: product,
                color: item.colorName.map { ProductColor(name: $0, hex: item.colorHex ?? "#999999") },
                size: item.size.flatMap(Size.init(rawValue:)),
                quantity: item.quantity
            )
        }
        return Order(
            id: id, number: number, items: lines, address: shippingAddress.toDomain(), payment: payment.toDomain(),
            shipping: ShippingOption(rawValue: shippingOption) ?? .standard,
            pricing: PriceBreakdown(
                subtotal: Decimal(subtotalCents) / 100, discount: Decimal(discountCents) / 100,
                shipping: Decimal(shippingCents) / 100, tax: Decimal(taxCents) / 100, total: Decimal(totalCents) / 100
            ),
            placedAt: placedAt, status: OrderStatus(rawValue: status) ?? .processing
        )
    }
}
