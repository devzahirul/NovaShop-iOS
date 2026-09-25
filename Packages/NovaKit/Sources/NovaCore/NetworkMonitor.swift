import Foundation
import Network
import Observation

/// Connectivity as the rest of the app sees it.
///
/// Important nuance: `NWPathMonitor` reporting a satisfied path means *a route exists*, not that our
/// server is reachable (captive portals, DNS failures, server outages). So this is used as a
/// **hint** — to show the offline banner and to trigger a sync the moment connectivity returns —
/// while correctness always comes from real request outcomes (failed syncs stay pending and retry).
@MainActor
@Observable
public final class NetworkMonitor {
    public enum Status: Equatable, Sendable {
        case unknown, online, offline
    }

    public private(set) var status: Status = .unknown
    /// Cellular / personal hotspot — defer large, non-urgent transfers.
    public private(set) var isExpensive = false
    /// Low Data Mode is on.
    public private(set) var isConstrained = false

    /// Debug-only switch that makes the app behave exactly as if it were offline (see `ConnectivityGate`).
    public var isSimulatingOffline: Bool {
        get { gate.isSimulatingOffline }
        set {
            gate.isSimulatingOffline = newValue
            publish(status: newValue ? .offline : pathStatus)
        }
    }

    /// Treat "unknown" (first callback not yet delivered) as online: optimistic, and a failed request
    /// corrects it immediately. Blocking the first launch on the monitor would cost start-up time.
    public var isOnline: Bool {
        status != .offline
    }

    @ObservationIgnored public let gate: ConnectivityGate
    @ObservationIgnored private let monitor: NWPathMonitor?
    @ObservationIgnored private var pathStatus: Status = .unknown
    @ObservationIgnored private var continuations: [UUID: AsyncStream<Status>.Continuation] = [:]

    /// - Parameter monitoring: `false` for tests and previews — status is then driven manually.
    public init(monitoring: Bool = true, gate: ConnectivityGate = ConnectivityGate(), initialStatus: Status = .unknown) {
        self.gate = gate
        monitor = monitoring ? NWPathMonitor() : nil
        pathStatus = initialStatus
        status = initialStatus
    }

    public func start() {
        guard let monitor else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            // Extract plain values on the monitor's queue, then hop to the main actor.
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.apply(online: online, expensive: expensive, constrained: constrained)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.novashop.network-monitor", qos: .utility))
    }

    /// Emits every status change (not the current value). Each call returns an independent stream.
    public func changes() -> AsyncStream<Status> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations[id] = nil }
            }
        }
    }

    /// Test / preview hook.
    public func simulate(_ status: Status) {
        pathStatus = status
        publish(status: gate.isSimulatingOffline ? .offline : status)
    }

    private func apply(online: Bool, expensive: Bool, constrained: Bool) {
        isExpensive = expensive
        isConstrained = constrained
        pathStatus = online ? .online : .offline
        publish(status: gate.isSimulatingOffline ? .offline : pathStatus)
    }

    private func publish(status newStatus: Status) {
        guard newStatus != status else { return }
        Log.network.info("Connectivity: \(String(describing: newStatus), privacy: .public)")
        status = newStatus
        for continuation in continuations.values {
            continuation.yield(newStatus)
        }
    }
}

/// Thread-safe flag read by the HTTP transport on every request (off the main actor).
/// `@unchecked Sendable` is justified: the only state is guarded by `lock`.
public final class ConnectivityGate: @unchecked Sendable {
    private let lock = NSLock()
    private var simulatingOffline = false

    public init() {}

    public var isSimulatingOffline: Bool {
        get { lock.withLock { simulatingOffline } }
        set { lock.withLock { simulatingOffline = newValue } }
    }
}
