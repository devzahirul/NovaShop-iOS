/// Explicit screen state. Views switch over this instead of juggling `isLoading` / `error` / `data?`
/// optionals, which makes impossible states (loading *and* failed) unrepresentable.
public enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(UserFacingError)

    public var value: Value? {
        if case let .loaded(value) = self {
            return value
        }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    public var error: UserFacingError? {
        if case let .failed(error) = self {
            return error
        }
        return nil
    }
}

extension LoadState: Sendable where Value: Sendable {}
extension LoadState: Equatable where Value: Equatable {}

/// The only error shape a view ever renders. Mapping from domain / transport errors happens in the
/// view model, so copywriting lives in one place and raw `Error.localizedDescription` never leaks.
public struct UserFacingError: Error, Equatable, Sendable {
    public let title: String
    public let message: String
    public let isRetryable: Bool

    public init(title: String = "Something went wrong", message: String, isRetryable: Bool = true) {
        self.title = title
        self.message = message
        self.isRetryable = isRetryable
    }

    public static let offline = UserFacingError(
        title: "You're offline",
        message: "Check your connection and try again."
    )

    public static let generic = UserFacingError(message: "Please try again in a moment.")
}

/// Errors that know how to describe themselves to a user.
public protocol UserFacingConvertible: Error {
    var userFacing: UserFacingError { get }
}

public extension Error {
    var userFacing: UserFacingError {
        (self as? any UserFacingConvertible)?.userFacing ?? .generic
    }
}
