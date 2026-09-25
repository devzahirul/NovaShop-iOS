import Foundation

// MARK: - Cart

public struct CartItem: Identifiable, Hashable, Sendable, Codable {
    /// A cart line is unique per product + colour + size.
    public var id: String {
        "\(product.id.rawValue)|\(color?.name ?? "-")|\(size?.rawValue ?? "-")"
    }

    public let product: Product
    public let color: ProductColor?
    public let size: Size?
    public var quantity: Int

    public init(product: Product, color: ProductColor?, size: Size?, quantity: Int = 1) {
        self.product = product
        self.color = color
        self.size = size
        self.quantity = quantity
    }

    public var lineTotal: Decimal {
        product.price * Decimal(quantity)
    }

    public var variantDescription: String {
        [color?.name, size?.rawValue].compactMap { $0 }.joined(separator: " / ")
    }
}

// MARK: - Pricing

public struct Coupon: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        /// 0...1, e.g. 0.2 for 20 % off.
        case percentage(Decimal)
        case fixedAmount(Decimal)
    }

    public let code: String
    public let kind: Kind
    public let minimumSubtotal: Decimal

    public init(code: String, kind: Kind, minimumSubtotal: Decimal = 0) {
        self.code = code
        self.kind = kind
        self.minimumSubtotal = minimumSubtotal
    }

    public var headline: String {
        switch kind {
        case let .percentage(rate): "\((rate * 100).formatted())% off your order"
        case let .fixedAmount(amount): "\(amount.formatted(.currency(code: "USD"))) off your order"
        }
    }
}

public enum ShippingOption: String, CaseIterable, Identifiable, Sendable, Codable {
    case standard, express

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .standard: "Standard Shipping"
        case .express: "Express Shipping"
        }
    }

    public var eta: String {
        switch self {
        case .standard: "5-7 business days"
        case .express: "2-3 business days"
        }
    }

    public var price: Decimal {
        switch self {
        case .standard: 0
        case .express: 12
        }
    }
}

public struct PriceBreakdown: Hashable, Sendable, Codable {
    public let subtotal: Decimal
    public let discount: Decimal
    /// `nil` until a shipping option is chosen ("Calculated at next step").
    public let shipping: Decimal?
    public let tax: Decimal
    public let total: Decimal

    public init(subtotal: Decimal, discount: Decimal, shipping: Decimal?, tax: Decimal, total: Decimal) {
        self.subtotal = subtotal
        self.discount = discount
        self.shipping = shipping
        self.tax = tax
        self.total = total
    }

    public static let zero = PriceBreakdown(subtotal: 0, discount: 0, shipping: nil, tax: 0, total: 0)
}

// MARK: - Profile

public struct Address: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var fullName: String
    public var line1: String
    public var line2: String
    public var city: String
    public var state: String
    public var postalCode: String
    public var country: String
    public var isDefault: Bool

    public init(
        id: UUID = UUID(), fullName: String, line1: String, line2: String = "", city: String, state: String,
        postalCode: String, country: String = "United States", isDefault: Bool = false
    ) {
        self.id = id
        self.fullName = fullName
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.isDefault = isDefault
    }

    public var formattedLines: [String] {
        [line1, line2.isEmpty ? nil : line2, "\(city), \(state) \(postalCode)", country].compactMap { $0 }
    }
}

public enum CardBrand: String, Sendable, Codable, Hashable {
    case visa, mastercard, amex, discover, unknown

    public var displayName: String {
        switch self {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "American Express"
        case .discover: "Discover"
        case .unknown: "Card"
        }
    }
}

public struct PaymentMethod: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        /// We only ever persist a network token + last four. PAN / CVV never touch disk.
        case card(brand: CardBrand, last4: String, expiry: String, holder: String)
        case applePay
        case payPal
    }

    public let id: UUID
    public let kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public var title: String {
        switch kind {
        case let .card(brand, last4, _, _): "\(brand.displayName) •••• \(last4)"
        case .applePay: "Apple Pay"
        case .payPal: "PayPal"
        }
    }

    public static let applePay = PaymentMethod(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A991")!, kind: .applePay)
    public static let payPal = PaymentMethod(id: UUID(uuidString: "00000000-0000-0000-0000-0000000FA7A1")!, kind: .payPal)
}

public struct User: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var email: String
    public var stylePreferences: Set<StylePreference>

    public init(id: UUID = UUID(), name: String, email: String, stylePreferences: Set<StylePreference> = []) {
        self.id = id
        self.name = name
        self.email = email
        self.stylePreferences = stylePreferences
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

public enum StylePreference: String, CaseIterable, Identifiable, Sendable, Codable {
    case casual, chic, minimal, trendy, classic, boho

    public var id: String {
        rawValue
    }

    public var title: String {
        rawValue.capitalized
    }
}

// MARK: - Orders

public enum OrderStatus: String, CaseIterable, Sendable, Codable {
    case placed, processing, shipped, outForDelivery, delivered, cancelled

    public var title: String {
        switch self {
        case .placed: "Order Placed"
        case .processing: "Processing"
        case .shipped: "Shipped"
        case .outForDelivery: "Out for Delivery"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    /// Linear fulfilment steps rendered by the tracking timeline.
    public static let trackingSteps: [OrderStatus] = [.placed, .processing, .shipped, .outForDelivery, .delivered]
}

public struct Order: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let number: String
    public let items: [CartItem]
    public let address: Address
    public let payment: PaymentMethod
    public let shipping: ShippingOption
    public let pricing: PriceBreakdown
    public let placedAt: Date
    public var status: OrderStatus

    public init(
        id: UUID = UUID(), number: String, items: [CartItem], address: Address, payment: PaymentMethod,
        shipping: ShippingOption, pricing: PriceBreakdown, placedAt: Date, status: OrderStatus
    ) {
        self.id = id
        self.number = number
        self.items = items
        self.address = address
        self.payment = payment
        self.shipping = shipping
        self.pricing = pricing
        self.placedAt = placedAt
        self.status = status
    }

    public var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
}

/// Everything needed to place an order, assembled by checkout.
public struct OrderDraft: Sendable, Equatable {
    public let items: [CartItem]
    public let address: Address
    public let payment: PaymentMethod
    public let shipping: ShippingOption
    public let coupon: Coupon?

    public init(items: [CartItem], address: Address, payment: PaymentMethod, shipping: ShippingOption, coupon: Coupon?) {
        self.items = items
        self.address = address
        self.payment = payment
        self.shipping = shipping
        self.coupon = coupon
    }
}

// MARK: - Content

public struct Review: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let productID: Product.ID
    public let author: String
    public let rating: Int
    public let body: String
    public let date: Date
    public let isVerified: Bool
    public let photoURLs: [URL]

    public init(
        id: String, productID: Product.ID, author: String, rating: Int, body: String, date: Date,
        isVerified: Bool, photoURLs: [URL] = []
    ) {
        self.id = id
        self.productID = productID
        self.author = author
        self.rating = rating
        self.body = body
        self.date = date
        self.isVerified = isVerified
        self.photoURLs = photoURLs
    }
}

public struct AppNotification: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable { case order, promotion, system }

    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let date: Date
    public var isRead: Bool

    public init(id: String, kind: Kind, title: String, body: String, date: Date, isRead: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.date = date
        self.isRead = isRead
    }
}
