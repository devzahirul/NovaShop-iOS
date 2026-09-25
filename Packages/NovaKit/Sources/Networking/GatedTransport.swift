import Foundation
import NovaCore

/// Wraps a transport and fails fast with `.offline` while connectivity is (simulated) offline —
/// so "offline mode" can be demoed and tested without toggling airplane mode, and the app takes
/// exactly the same code path it would on a real dead network.
public struct GatedTransport: HTTPTransport {
    private let base: any HTTPTransport
    private let gate: ConnectivityGate

    public init(_ base: any HTTPTransport, gate: ConnectivityGate) {
        self.base = base
        self.gate = gate
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if gate.isSimulatingOffline {
            throw APIError.offline
        }
        return try await base.send(request)
    }
}
