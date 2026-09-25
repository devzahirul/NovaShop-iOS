import OSLog

/// Signpost instrumentation. Every interval shows up in Instruments under
/// **Points of Interest**, lined up against Time Profiler, Hangs and the SwiftUI template.
///
/// Intervals we care about:
/// - `Launch.FirstFrame`   — `App.init` → first `RootView.onAppear`
/// - `Launch.HomeContent`  — first frame → home feed rendered with real data
/// - `Image.Fetch` / `Image.Decode` — network vs. ImageIO downsample cost per image
/// - `Catalog.Search`      — filter + sort cost, guarded by a unit-test budget
public enum Perf {
    public static let signposter = OSSignposter(subsystem: Log.subsystem, category: .pointsOfInterest)

    /// Measures an async operation as a signpost interval.
    ///
    /// `isolation: #isolation` makes the function run on the *caller's* actor, so a `@MainActor`
    /// caller can pass a non-Sendable closure without an actor hop or a data-race diagnostic.
    @inlinable
    public static func measure<T>(
        _ name: StaticString,
        isolation _: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }

    /// Measures a synchronous operation as a signpost interval.
    @inlinable
    public static func measureSync<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    public static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

/// Tracks the launch timeline in-process so the Developer menu can show it, and so it lands in logs
/// for CI launch regression checks. MetricKit reports the field-truth version (`MXAppLaunchMetric`).
@MainActor
public final class LaunchTimeline {
    public static let shared = LaunchTimeline()

    public private(set) var processStart: ContinuousClock.Instant = .now
    public private(set) var firstFrame: Duration?
    public private(set) var contentReady: Duration?

    private var launchState: OSSignpostIntervalState?
    private var contentState: OSSignpostIntervalState?

    private init() {}

    /// Called from `App.init` — the earliest point we control after `main`.
    public func markAppInit() {
        processStart = .now
        launchState = Perf.signposter.beginInterval("Launch.FirstFrame", id: Perf.signposter.makeSignpostID())
    }

    public func markFirstFrame() {
        guard firstFrame == nil else { return }
        let elapsed = processStart.duration(to: .now)
        firstFrame = elapsed
        if let launchState {
            Perf.signposter.endInterval("Launch.FirstFrame", launchState)
        }
        contentState = Perf.signposter.beginInterval("Launch.HomeContent", id: Perf.signposter.makeSignpostID())
        Log.performance.info("First frame after \(elapsed.formattedMilliseconds, privacy: .public)")
    }

    public func markContentReady() {
        guard contentReady == nil, firstFrame != nil else { return }
        let elapsed = processStart.duration(to: .now)
        contentReady = elapsed
        if let contentState {
            Perf.signposter.endInterval("Launch.HomeContent", contentState)
        }
        Log.performance.info("Home content ready after \(elapsed.formattedMilliseconds, privacy: .public)")
    }
}

public extension Duration {
    var formattedMilliseconds: String {
        let ms = Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
        return String(format: "%.0f ms", ms)
    }
}
