import Foundation
import NovaCore

/// A structured error body returned by the server (PostgREST: `{code, message, details, hint}`,
/// GoTrue: `{error_code, msg}` / `{error, error_description}`), normalised to one shape.
public struct ServerError: Equatable, Sendable {
    public let status: Int
    public let code: String?
    public let message: String?
    public let detail: String?

    public init(status: Int, code: String? = nil, message: String? = nil, detail: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.detail = detail
    }

    /// Parses any of the backend's error body shapes; `nil` when the body isn't a JSON error object.
    public static func parse(status: Int, data: Data) -> ServerError? {
        guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let code = (object["error_code"] as? String) ?? (object["code"] as? String) ?? (object["error"] as? String)
        let message = (object["message"] as? String) ?? (object["msg"] as? String) ?? (object["error_description"] as? String)
        let detail = (object["details"] as? String) ?? (object["hint"] as? String)
        guard code != nil || message != nil else { return nil }
        return ServerError(status: status, code: code, message: message, detail: detail)
    }
}

public enum APIError: Error, Equatable, Sendable, UserFacingConvertible {
    case invalidRequest
    case offline
    case timedOut
    /// 401 that survived a credential refresh — the session is gone.
    case unauthorized
    /// Non-2xx without a structured body.
    case http(status: Int)
    /// Non-2xx with a structured body the domain layer can map (e.g. `out_of_stock`).
    case server(ServerError)
    case decoding(String)
    case transport(String)

    public var status: Int? {
        switch self {
        case let .http(status): status
        case let .server(error): error.status
        case .unauthorized: 401
        default: nil
        }
    }

    public var userFacing: UserFacingError {
        switch self {
        case .offline: .offline
        case .timedOut: UserFacingError(title: "Taking too long", message: "The server didn't respond. Please try again.")
        case .unauthorized:
            UserFacingError(title: "Session expired", message: "Please sign in again to continue.", isRetryable: false)
        default:
            if let status, status >= 500 {
                UserFacingError(message: "Our servers are having a moment. Please try again.")
            } else {
                .generic
            }
        }
    }

    /// Worth retrying later: the request may succeed unchanged (network blip, overload, timeout).
    public var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .transport: true
        default: status.map { $0 == 408 || $0 == 429 || $0 >= 500 } ?? false
        }
    }

    /// The server understood and *rejected* the request (validation, constraint, not found).
    /// Retrying the same payload will fail again — the client must reconcile instead.
    public var isClientRejection: Bool {
        guard let status else { return false }
        return (400 ..< 500).contains(status) && ![401, 408, 429].contains(status)
    }
}

/// Abstracts "send bytes, get bytes". `URLSession` in production, fixtures in the portfolio build,
/// a closure-backed stub in tests. The client above it never knows which.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Adds credentials to requests and recovers from `401`s. Implemented by the auth layer
/// (Supabase: `apikey` + bearer token, single-flight token refresh).
public protocol RequestAuthorizing: Sendable {
    func authorize(_ request: URLRequest) async throws -> URLRequest
    /// Called once after a `401`. Return `true` if fresh credentials exist and the request should be retried.
    func refreshAfterUnauthorized(_ request: URLRequest) async -> Bool
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("Non-HTTP response") }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost,
                 .internationalRoamingOff:
                throw APIError.offline
            case .timedOut: throw APIError.timedOut
            case .cancelled: throw CancellationError()
            default: throw APIError.transport(error.localizedDescription)
            }
        }
    }
}

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(300)) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    /// Exponential backoff: 300 ms, 600 ms, 1.2 s …
    func delay(forAttempt attempt: Int) -> Duration {
        baseDelay * (1 << (attempt - 1))
    }
}

/// Stateless, `Sendable` API client. Methods are `nonisolated async`, so request building, the
/// network wait and — importantly — JSON decoding all run on the cooperative pool, never on the
/// main actor, no matter who calls them.
///
/// Request pipeline: build → authorize → send → (401? refresh once → re-authorize → resend)
/// → (transient & retry-safe? backoff → resend) → decode.
public struct APIClient: Sendable {
    public let baseURL: URL
    private let transport: any HTTPTransport
    private let retryPolicy: RetryPolicy
    private let clock: any Clock<Duration>
    private let authorizer: (any RequestAuthorizing)?

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        retryPolicy: RetryPolicy = RetryPolicy(),
        clock: any Clock<Duration> = ContinuousClock(),
        authorizer: (any RequestAuthorizing)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.clock = clock
        self.authorizer = authorizer
    }

    public func send<Response>(_ endpoint: Endpoint<Response>, decoder: JSONDecoder = .api) async throws -> Response {
        let baseRequest = try endpoint.makeRequest(baseURL: baseURL)
        let attempts = endpoint.isRetrySafe ? retryPolicy.maxAttempts : 1
        var attempt = 1
        var hasRefreshedCredentials = false

        while true {
            try Task.checkCancellation()
            let request = try await authorizer?.authorize(baseRequest) ?? baseRequest
            do {
                return try await perform(request, decoder: decoder)
            } catch let error as APIError where error.status == 401 {
                guard let authorizer, !hasRefreshedCredentials, await authorizer.refreshAfterUnauthorized(request) else {
                    throw authorizer == nil ? error : APIError.unauthorized
                }
                hasRefreshedCredentials = true
            } catch let error as APIError where error.isTransient && error != .offline && attempt < attempts {
                Log.network
                    .notice("Retrying \(request.url?.path() ?? "", privacy: .public) after \(String(describing: error), privacy: .public)")
                try await clock.sleep(for: retryPolicy.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    private func perform<Response: Decodable>(_ request: URLRequest, decoder: JSONDecoder) async throws -> Response {
        let (data, response) = try await transport.send(request)
        Log.network
            .debug("\(request.httpMethod ?? "", privacy: .public) \(request.url?.path() ?? "", privacy: .public) → \(response.statusCode)")

        guard (200 ..< 300).contains(response.statusCode) else {
            if let serverError = ServerError.parse(status: response.statusCode, data: data) {
                throw APIError.server(serverError)
            }
            throw APIError.http(status: response.statusCode)
        }
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            Log.network.error("Decoding \(Response.self) failed: \(String(describing: error), privacy: .public)")
            throw APIError.decoding(String(describing: Response.self))
        }
    }
}

public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
