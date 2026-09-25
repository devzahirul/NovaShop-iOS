import Foundation
@testable import Networking
import Testing
import TestSupport

/// Transport stub that replays a scripted sequence of responses and records requests.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    enum Step {
        case status(Int, Data = Data())
        case failure(any Error)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let step: Step = lock.withLock {
            requests.append(request)
            return steps.isEmpty ? .status(500) : steps.removeFirst()
        }
        switch step {
        case let .status(code, data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case let .failure(error):
            throw error
        }
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }
}

struct Item: Codable, Equatable, Sendable {
    let productName: String
}

@Suite("APIClient")
struct APIClientTests {
    let base = URL(string: "https://api.example.com")!

    func client(_ transport: ScriptedTransport, attempts: Int = 3) -> APIClient {
        APIClient(baseURL: base, transport: transport, retryPolicy: RetryPolicy(maxAttempts: attempts), clock: ImmediateClock())
    }

    @Test("Decodes snake_case JSON into the endpoint's response type")
    func decodes() async throws {
        let transport = ScriptedTransport([.status(200, Data(#"{"product_name":"Isla"}"#.utf8))])
        let item = try await client(transport).send(Endpoint<Item>(path: "v1/item"))
        #expect(item == Item(productName: "Isla"))
        #expect(transport.requests.first?.url?.absoluteString == "https://api.example.com/v1/item")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Retries transient 5xx for GET and then succeeds")
    func retriesTransient() async throws {
        let transport = ScriptedTransport([.status(503), .status(502), .status(200, Data(#"{"product_name":"Luna"}"#.utf8))])
        let item = try await client(transport).send(Endpoint<Item>(path: "v1/item"))
        #expect(item.productName == "Luna")
        #expect(transport.requestCount == 3)
    }

    @Test("Never retries non-idempotent POST — no double charges")
    func noRetryForPost() async {
        let transport = ScriptedTransport([.status(503), .status(200)])
        await #expect(throws: APIError.http(status: 503)) {
            try await client(transport).send(Endpoint<EmptyResponse>(path: "v1/orders", method: .post))
        }
        #expect(transport.requestCount == 1)
    }

    @Test("4xx fails fast without retrying")
    func clientErrorsFailFast() async {
        let transport = ScriptedTransport([.status(404)])
        await #expect(throws: APIError.http(status: 404)) {
            try await client(transport).send(Endpoint<Item>(path: "v1/item"))
        }
        #expect(transport.requestCount == 1)
    }

    @Test("Malformed payloads surface a decoding error, not a crash")
    func decodingError() async {
        let transport = ScriptedTransport([.status(200, Data("{}".utf8))])
        await #expect(throws: APIError.decoding("Item")) {
            try await client(transport).send(Endpoint<Item>(path: "v1/item"))
        }
    }

    @Test("Gives up after the retry budget")
    func retryBudget() async {
        let transport = ScriptedTransport([.status(500), .status(500), .status(500), .status(200)])
        await #expect(throws: APIError.http(status: 500)) {
            try await client(transport).send(Endpoint<Item>(path: "v1/item"))
        }
        #expect(transport.requestCount == 3)
    }

    @Test("Query items and JSON bodies are encoded")
    func requestBuilding() throws {
        let endpoint = try Endpoint<EmptyResponse>.json(path: "v1/search", method: .post, body: ["query_text": "linen"])
        let request = try endpoint.makeRequest(baseURL: base)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let withQuery = try Endpoint<Item>(path: "v1/items", queryItems: [URLQueryItem(name: "q", value: "linen dress")])
            .makeRequest(baseURL: base)
        #expect(withQuery.url?.absoluteString == "https://api.example.com/v1/items?q=linen%20dress")
    }

    @Test("Offline errors map to a friendly, retryable message")
    func userFacing() {
        #expect(APIError.offline.userFacing.title == "You're offline")
        #expect(APIError.http(status: 503).userFacing.isRetryable)
    }
}
