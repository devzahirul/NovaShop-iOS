import Foundation

/// Runtime configuration resolved once at launch from launch arguments / environment.
/// UI tests and performance runs flip behaviour here — never with `#if DEBUG` scattered in features.
public struct AppConfiguration: Sendable, Equatable {
    public enum Environment: String, Sendable {
        /// Bundled fixtures served through the real networking stack — works with no backend at all.
        case fixtures
        /// Supabase (Postgres + Auth + RLS) at `apiBaseURL` with the publishable key.
        case supabase
    }

    public var environment: Environment
    public var apiBaseURL: URL
    /// Supabase publishable (anon) key — safe to ship; Row Level Security is the real gate.
    public var supabasePublishableKey: String
    /// Artificial latency applied by the fixture transport so loading states are visible and realistic.
    public var simulatedLatency: Duration
    /// Use in-memory persistence and wipe state — deterministic UI tests.
    public var isUITesting: Bool
    /// Start signed in (skips auth in UI tests / screenshots).
    public var startSignedIn: Bool

    public init(
        environment: Environment = .fixtures,
        apiBaseURL: URL = URL(string: "https://api.novashop.example")!,
        supabasePublishableKey: String = "",
        simulatedLatency: Duration = .milliseconds(350),
        isUITesting: Bool = false,
        startSignedIn: Bool = false
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.supabasePublishableKey = supabasePublishableKey
        self.simulatedLatency = simulatedLatency
        self.isUITesting = isUITesting
        self.startSignedIn = startSignedIn
    }

    public enum LaunchArgument {
        public static let uiTesting = "-ui-testing"
        public static let signedIn = "-signed-in"
        public static let noLatency = "-no-latency"
    }

    public enum InfoKey {
        public static let supabaseHost = "NovaShopSupabaseHost"
        public static let supabaseKey = "NovaShopSupabasePublishableKey"
    }

    /// Resolves configuration from the process. Pure function of its inputs → unit-testable.
    ///
    /// Supabase is enabled when the build carries a host + publishable key (from the git-ignored
    /// `Config/Supabase.local.xcconfig`). UI tests always use fixtures so they're deterministic.
    public static func resolve(arguments: [String], environment env: [String: String], info: [String: Any] = [:]) -> AppConfiguration {
        var config = AppConfiguration()
        config.isUITesting = arguments.contains(LaunchArgument.uiTesting)
        config.startSignedIn = arguments.contains(LaunchArgument.signedIn)
        if arguments.contains(LaunchArgument.noLatency) || config.isUITesting {
            config.simulatedLatency = .zero
        }
        let host = (env["NOVASHOP_SUPABASE_HOST"] ?? info[InfoKey.supabaseHost] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (env["NOVASHOP_SUPABASE_KEY"] ?? info[InfoKey.supabaseKey] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if !config.isUITesting, !host.isEmpty, !key.isEmpty, let url = URL(string: "https://\(host)") {
            config.environment = .supabase
            config.apiBaseURL = url
            config.supabasePublishableKey = key
            config.simulatedLatency = .zero
        }
        return config
    }

    public static var current: AppConfiguration {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment,
            info: Bundle.main.infoDictionary ?? [:]
        )
    }
}
