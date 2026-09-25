import Foundation
import NovaCore

// Ports. Features depend only on these protocols; `Data` provides the adapters and the app's
// composition root picks which ones to plug in (fixtures, live API, in-memory for tests).
// Every protocol is `Sendable` so implementations can be actors and be called from any isolation.

public protocol CatalogRepository: Sendable {
    func categories() async throws -> [ProductCategory]
    func products() async throws -> [Product]
    func product(id: Product.ID) async throws -> Product
    func search(_ query: ProductQuery) async throws -> [Product]
    func collections() async throws -> [EditorialCollection]
    func reviews(for productID: Product.ID) async throws -> ReviewPage
    func popularSearches() async throws -> [String]
}

public protocol AuthService: Sendable {
    func restoreSession() async -> User?
    func signIn(email: String, password: String) async throws -> User
    func signUp(name: String, email: String, password: String) async throws -> User
    func signIn(with provider: SocialProvider) async throws -> User
    func update(_ user: User) async throws -> User
    func signOut() async
    func deleteAccount() async throws
}

public enum SocialProvider: String, Sendable {
    case apple, google
}

public enum AuthError: Error, Equatable, Sendable, UserFacingConvertible {
    case invalidCredentials
    case emailAlreadyInUse
    case cancelled
    case network

    public var userFacing: UserFacingError {
        switch self {
        case .invalidCredentials:
            UserFacingError(title: "Couldn't sign in", message: "That email and password don't match.", isRetryable: false)
        case .emailAlreadyInUse:
            UserFacingError(
                title: "Account exists",
                message: "An account with this email already exists. Try signing in.",
                isRetryable: false
            )
        case .cancelled:
            UserFacingError(title: "Cancelled", message: "Sign in was cancelled.", isRetryable: false)
        case .network:
            .offline
        }
    }
}

public protocol CouponService: Sendable {
    func validate(code: String, subtotal: Decimal) async throws -> Coupon
}

public enum CouponError: Error, Equatable, Sendable, UserFacingConvertible {
    case notFound
    case minimumNotMet(Decimal)

    public var userFacing: UserFacingError {
        switch self {
        case .notFound:
            UserFacingError(title: "Invalid code", message: "This coupon code isn't valid.", isRetryable: false)
        case let .minimumNotMet(minimum):
            UserFacingError(
                title: "Not eligible yet",
                message: "Spend \(minimum.formatted(.currency(code: "USD"))) or more to use this code.",
                isRetryable: false
            )
        }
    }
}

public protocol OrderService: Sendable {
    func placeOrder(_ draft: OrderDraft) async throws -> Order
    func orders() async throws -> [Order]
}

public enum PaymentError: Error, Equatable, Sendable, UserFacingConvertible {
    case declined

    public var userFacing: UserFacingError {
        UserFacingError(title: "Payment declined", message: "Your bank declined this payment. Try another method.")
    }
}

public protocol ProfileRepository: Sendable {
    func addresses() async -> [Address]
    func save(_ address: Address) async throws -> [Address]
    func deleteAddress(id: Address.ID) async throws -> [Address]
    func paymentMethods() async -> [PaymentMethod]
    func save(_ method: PaymentMethod) async throws -> [PaymentMethod]
}

public protocol NotificationRepository: Sendable {
    func notifications() async throws -> [AppNotification]
}

/// Generic persistence port for small documents (cart, wishlist, recents).
/// Primary associated type → call sites write `any Persisting<[CartItem]>`.
public protocol Persisting<Value>: Sendable {
    associatedtype Value: Sendable
    func load() async -> Value?
    func save(_ value: Value) async throws
}
