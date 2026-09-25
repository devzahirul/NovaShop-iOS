import Foundation
import NovaCore

public enum APIError: Error, Equatable, Sendable, UserFacingConvertible {
    case invalidRequest
    case offline
    case timedOut
    case http(status: Int)
    case decoding(String)
    case transport(String)

    public var userFacing: UserFacingError {
        switch self {
        case .offline: .offline
        case .timedOut: UserFacingError(title: "Taking too long", message: "The server didn't respond. Please try again.")
        case let .http(status) where status >= 500: UserFacingError(message: "Our servers are having a moment. Please try again.")
        default: .generic
        }
    }

    var isTransient: Bool {
        switch self {
        case .timedOut, .transport: true
        case let .http(status): status == 429 || status >= 500
        default: false
        }
    }
}

/// Abstracts "send bytes, get bytes". `URLSession` in production, fixtures in the portfolio build,
/// a closure-backed stub in tests. The client above it never knows which.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
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
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw APIError.offline
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
public struct APIClient: Sendable {
    public let baseURL: URL
    private let transport: any HTTPTransport
    private let retryPolicy: RetryPolicy
    private let clock: any Clock<Duration>

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        retryPolicy: RetryPolicy = RetryPolicy(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.clock = clock
    }

    public func send<Response>(_ endpoint: Endpoint<Response>, decoder: JSONDecoder = .api) async throws -> Response {
        let request = try endpoint.makeRequest(baseURL: baseURL)
        let attempts = endpoint.method.isIdempotent ? retryPolicy.maxAttempts : 1
        var attempt = 1

        while true {
            try Task.checkCancellation()
            do {
                return try await perform(request, decoder: decoder)
            } catch let error as APIError where error.isTransient && attempt < attempts {
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
