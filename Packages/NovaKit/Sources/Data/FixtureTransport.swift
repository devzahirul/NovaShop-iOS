import Foundation
import Networking
import NovaCore

/// Serves bundled JSON through the *real* `APIClient` → DTO → mapping pipeline.
///
/// This is deliberately a transport, not a fake repository: decoding, error mapping, retries and
/// threading behave exactly as they would against production. Swapping to a live backend is a
/// one-line change in the composition root (`URLSessionTransport`).
public struct FixtureTransport: HTTPTransport {
    private let latency: Duration
    private let bundle: Bundle

    public init(latency: Duration = .milliseconds(350), bundle: Bundle? = nil) {
        self.latency = latency
        self.bundle = bundle ?? .module
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        guard let url = request.url else { throw APIError.invalidRequest }
        let segments = url.pathComponents.filter { $0 != "/" }

        let data: Data
        switch segments {
        case ["v1", "catalog"]:
            data = try load("catalog")
        case ["v1", "notifications"]:
            data = try load("notifications")
        case let path where path.count == 4 && path[1] == "products" && path[3] == "reviews":
            data = try reviewsPage(productID: path[2])
        default:
            return (Data(), response(url, status: 404))
        }
        return (data, response(url, status: 200))
    }

    private func load(_ name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw APIError.transport("Missing fixture \(name).json")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func reviewsPage(productID: String) throws -> Data {
        let all = try JSONSerialization.jsonObject(with: load("reviews")) as? [String: Any]
        let page = all?[productID] ?? ["summary": ["average": 0, "total": 0, "distribution": [:]], "items": []]
        return try JSONSerialization.data(withJSONObject: page)
    }

    private func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
}
