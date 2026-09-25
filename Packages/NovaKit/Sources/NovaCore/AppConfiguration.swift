import Foundation

/// Runtime configuration resolved once at launch from launch arguments / environment.
/// UI tests and performance runs flip behaviour here — never with `#if DEBUG` scattered in features.
public struct AppConfiguration: Sendable, Equatable {
    public enum Environment: String, Sendable {
        /// Bundled fixtures served through the real networking stack (default for the portfolio build).
        case fixtures
        /// A real backend at `apiBaseURL`.
        case production
    }

    public var environment: Environment
    public var apiBaseURL: URL
    /// Artificial latency applied by the fixture transport so loading states are visible and realistic.
    public var simulatedLatency: Duration
    /// Use in-memory persistence and wipe state — deterministic UI tests.
    public var isUITesting: Bool
    /// Start signed in (skips auth in UI tests / screenshots).
    public var startSignedIn: Bool

    public init(
        environment: Environment = .fixtures,
        apiBaseURL: URL = URL(string: "https://api.novashop.example")!,
        simulatedLatency: Duration = .milliseconds(350),
        isUITesting: Bool = false,
        startSignedIn: Bool = false
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.simulatedLatency = simulatedLatency
        self.isUITesting = isUITesting
        self.startSignedIn = startSignedIn
    }

    public enum LaunchArgument {
        public static let uiTesting = "-ui-testing"
        public static let signedIn = "-signed-in"
        public static let noLatency = "-no-latency"
    }

    /// Resolves configuration from the process. Pure function of its inputs → unit-testable.
    public static func resolve(arguments: [String], environment env: [String: String]) -> AppConfiguration {
        var config = AppConfiguration()
        config.isUITesting = arguments.contains(LaunchArgument.uiTesting)
        config.startSignedIn = arguments.contains(LaunchArgument.signedIn)
        if arguments.contains(LaunchArgument.noLatency) || config.isUITesting {
            config.simulatedLatency = .zero
        }
        if let base = env["NOVASHOP_API_BASE_URL"], let url = URL(string: base) {
            config.environment = .production
            config.apiBaseURL = url
        }
        return config
    }

    public static var current: AppConfiguration {
        resolve(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }
}
