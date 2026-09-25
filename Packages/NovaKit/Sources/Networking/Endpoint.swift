import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"

    /// Only idempotent requests are retried automatically.
    public var isIdempotent: Bool {
        self == .get || self == .put || self == .delete
    }
}

/// A typed description of one API call. The response type is carried in the generic parameter,
/// so `client.send(.products)` returns `[ProductDTO]` with no casting at call sites.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval
    /// Whether the client may automatically resend after a transient failure. Defaults to the
    /// method's idempotency; a `POST` carrying an idempotency key (checkout) can opt in explicitly.
    public var isRetrySafe: Bool

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 15,
        isRetrySafe: Bool? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.isRetrySafe = isRetrySafe ?? method.isIdempotent
    }

    public func makeRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
            // URLComponents leaves "+" unescaped, which servers decode as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.invalidRequest }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

public extension Endpoint {
    static func json(
        path: String,
        method: HTTPMethod,
        body: some Encodable,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        isRetrySafe: Bool? = nil,
        encoder: JSONEncoder = .api
    ) throws -> Endpoint {
        try Endpoint(
            path: path, method: method, queryItems: queryItems, headers: headers, body: encoder.encode(body),
            isRetrySafe: isRetrySafe
        )
    }
}

public extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        // Postgres timestamps carry microseconds ("…T10:04:05.123456+00:00"); plain `.iso8601` rejects them.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601Formatters.parse(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

enum ISO8601Formatters {
    /// ISO8601DateFormatter is documented thread-safe; it just isn't annotated `Sendable`.
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? whole.date(from: string)
    }
}

public extension JSONEncoder {
    static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
