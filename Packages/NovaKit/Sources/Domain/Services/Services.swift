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
    /// Whether Sign in with Apple / Google are configured for this backend (hidden in the UI otherwise).
    var supportsSocialSignIn: Bool { get }
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
    /// Sign-up succeeded but the backend requires email confirmation before a session is issued.
    case confirmationRequired(email: String)
    case emailNotConfirmed
    case weakPassword(String)
    case rateLimited
    case sessionExpired
    case unsupportedProvider
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
        case let .confirmationRequired(email):
            UserFacingError(
                title: "Check your inbox",
                message: "We sent a confirmation link to \(email). Confirm it, then sign in.",
                isRetryable: false
            )
        case .emailNotConfirmed:
            UserFacingError(title: "Confirm your email", message: "Open the link we emailed you, then sign in.", isRetryable: false)
        case let .weakPassword(reason):
            UserFacingError(title: "Choose a stronger password", message: reason, isRetryable: false)
        case .rateLimited:
            UserFacingError(title: "Too many attempts", message: "Please wait a minute and try again.")
        case .sessionExpired:
            UserFacingError(title: "Session expired", message: "Please sign in again to continue.", isRetryable: false)
        case .unsupportedProvider:
            UserFacingError(title: "Not available", message: "This sign-in option isn't available yet.", isRetryable: false)
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

/// Checkout failures the server reports (it owns pricing, stock and the cart at order time).
public enum CheckoutError: Error, Equatable, Sendable, UserFacingConvertible {
    case offline
    case cartNotSynced
    case cartEmpty
    case outOfStock(products: String)
    case addressNotFound

    public var userFacing: UserFacingError {
        switch self {
        case .offline:
            UserFacingError(title: "You're offline", message: "Connect to the internet to complete checkout. Your bag is saved.")
        case .cartNotSynced:
            UserFacingError(
                title: "Couldn't update your bag",
                message: "We couldn't sync your bag with our servers. Please try again."
            )
        case .cartEmpty:
            UserFacingError(title: "Your bag is empty", message: "Add something to your bag to check out.", isRetryable: false)
        case let .outOfStock(products):
            UserFacingError(
                title: "Not enough stock",
                message: "\(products) \(products.contains(",") ? "are" : "is") no longer available in that quantity. "
                    + "Your bag has been updated.",
                isRetryable: false
            )
        case .addressNotFound:
            UserFacingError(title: "Address unavailable", message: "Please choose your shipping address again.", isRetryable: false)
        }
    }
}

public protocol ProfileRepository: Sendable {
    func addresses() async throws -> [Address]
    func save(_ address: Address) async throws -> [Address]
    func deleteAddress(id: Address.ID) async throws -> [Address]
    func paymentMethods() async throws -> [PaymentMethod]
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
