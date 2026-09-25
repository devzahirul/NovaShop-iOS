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

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 15
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public func makeRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
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
        encoder: JSONEncoder = .api
    ) throws -> Endpoint {
        try Endpoint(path: path, method: method, body: encoder.encode(body))
    }
}

public extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
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
