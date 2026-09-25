import OSLog

/// Structured, privacy-aware logging. `os.Logger` is lazily formatted and near zero cost when a
/// level is not being collected, so these calls are safe on hot paths. No `print` anywhere in the app.
///
/// Stream on a simulator:
/// `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.novashop.app"'`
public enum Log {
    public static let subsystem = "com.novashop.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let images = Logger(subsystem: subsystem, category: "images")
    public static let navigation = Logger(subsystem: subsystem, category: "navigation")
    public static let performance = Logger(subsystem: subsystem, category: "performance")
}
