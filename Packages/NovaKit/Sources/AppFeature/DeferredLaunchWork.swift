import MetricKit
import NovaCore

/// Work that must not compete with the first frames. Scheduled after `bootstrap()` at background
/// priority, so the scheduler runs it only when the main thread and user-initiated work are idle.
enum DeferredLaunchWork {
    @MainActor
    static func schedule() {
        Task(priority: .background) {
            MetricsSubscriber.shared.start()
        }
    }
}

/// Field performance telemetry. MetricKit delivers daily aggregates (launch time histograms, hang
/// rate, memory, disk writes) and diagnostics (crash / hang call stacks) from real devices.
/// In production these payloads are forwarded to the analytics backend; here they are logged.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = MetricsSubscriber()

    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let launch = payload.applicationLaunchMetrics {
                Log.performance
                    .info("MetricKit launch histogram: \(String(describing: launch.histogrammedTimeToFirstDraw), privacy: .public)")
            }
            if let responsiveness = payload.applicationResponsivenessMetrics {
                Log.performance
                    .info(
                        "MetricKit hang histogram: \(String(describing: responsiveness.histogrammedApplicationHangTime), privacy: .public)"
                    )
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            Log.performance.error("MetricKit diagnostic — crashes: \(crashes), hangs: \(hangs)")
        }
    }
}
