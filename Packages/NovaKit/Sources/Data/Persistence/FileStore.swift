import Domain
import Foundation
import NovaCore

/// Codable document persisted to Application Support.
///
/// - `actor` → reads/writes are serialised and always off the main thread.
/// - Atomic writes (`.atomic`) → a crash mid-write never leaves a half-written cart.
/// - `.completeFileProtectionUntilFirstUserAuthentication` → encrypted at rest, still readable for
///   background refresh after first unlock.
/// - Decoding failures (e.g. schema change) are logged and treated as "empty", never a crash loop.
public actor FileStore<Value: Codable & Sendable>: Persisting {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(filename: String, directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "NovaShop", directoryHint: .isDirectory).appending(path: "\(filename).json")
    }

    public func load() async -> Value? {
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Value.self, from: data)
        } catch {
            let file = url.lastPathComponent
            Log.persistence.error("Discarding unreadable \(file, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func save(_ value: Value) async throws {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func delete() throws {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Volatile store for UI tests and previews.
public actor InMemoryStore<Value: Sendable>: Persisting {
    private var value: Value?

    public init(_ value: Value? = nil) {
        self.value = value
    }

    public func load() async -> Value? {
        value
    }

    public func save(_ value: Value) async throws {
        self.value = value
    }
}
