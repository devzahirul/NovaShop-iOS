import Domain
import Foundation
import Networking
import NovaCore

/// Server side of a synced collection (REST in production, an in-memory fake in tests).
public protocol RemoteCollection<Record>: Sendable {
    associatedtype Record: Identifiable & Sendable where Record.ID: Sendable
    func fetchAll() async throws -> [Record]
    /// Idempotent: absolute values ("quantity = 3"), never deltas, so a retried push is harmless.
    func upsert(_ records: [Record]) async throws
    func delete(_ ids: [Record.ID]) async throws
}

/// On-device, persisted collection with per-record sync state. The reconciliation rules:
///
/// 1. **Push** pending upserts in one batch. If the server *rejects* the batch (4xx), retry each
///    record alone to isolate the offender; offenders are dropped locally and reported. Transient
///    errors (offline, 5xx, timeout) abort the pass — everything stays pending for next time.
/// 2. **Push** pending deletes.
/// 3. **Pull** the server state and reconcile:
///    - local `synced` record → replaced by the server's version (or dropped if it's gone —
///      deleted on another device);
///    - local pending record → kept: the user's most recent intent wins until it's pushed;
///    - server-only record → added (created on another device).
///
/// Versions make it safe against edits *during* a sync: a push only marks a record synced if its
/// version didn't change while the request was in flight (actor reentrancy lets edits interleave).
public actor SyncedCollection<Record: Identifiable & Codable & Sendable, Remote: RemoteCollection>: LocalFirstRepository
    where Record.ID: Codable & Sendable, Remote.Record == Record {
    struct Entry: Codable, Sendable {
        var record: Record
        var state: SyncState
        var version: Int
        /// Whether the server has (ever) acknowledged this record — local-only records can be
        /// deleted outright instead of queuing a remote delete.
        var existsRemotely: Bool
    }

    private let store: any Persisting<[Entry]>
    private let remote: Remote
    private let newestFirst: Bool
    private var entries: [Entry] = []
    private var isLoaded = false

    /// - Parameter newestFirst: new records are shown at the top (wishlist) instead of the bottom (cart).
    public init(remote: Remote, directory: URL? = nil, filename: String, inMemory: Bool = false, newestFirst: Bool = false) {
        self.remote = remote
        self.newestFirst = newestFirst
        store = inMemory ? InMemoryStore<[Entry]>() : FileStore<[Entry]>(filename: filename, directory: directory)
    }

    // MARK: LocalFirstRepository

    public func records() async -> [Record] {
        await loadIfNeeded()
        return entries.filter { $0.state != .pendingDelete }.map(\.record)
    }

    public func pendingIDs() async -> Set<Record.ID> {
        await loadIfNeeded()
        return Set(entries.filter { $0.state != .synced }.map(\.record.id))
    }

    public func save(_ record: Record) async {
        await loadIfNeeded()
        if let index = index(of: record.id) {
            entries[index].record = record
            entries[index].state = .pendingUpsert
            entries[index].version += 1
        } else {
            let entry = Entry(record: record, state: .pendingUpsert, version: 1, existsRemotely: false)
            if newestFirst {
                entries.insert(entry, at: 0)
            } else {
                entries.append(entry)
            }
        }
        await persist()
    }

    public func remove(_ id: Record.ID) async {
        await loadIfNeeded()
        guard let index = index(of: id) else { return }
        if entries[index].existsRemotely {
            entries[index].state = .pendingDelete
            entries[index].version += 1
        } else {
            entries.remove(at: index)
        }
        await persist()
    }

    public func removeAllLocally() async {
        await loadIfNeeded()
        entries = []
        await persist()
    }

    public func prepareForMerge() async {
        await loadIfNeeded()
        for index in entries.indices where entries[index].state != .pendingDelete {
            entries[index].state = .pendingUpsert
            entries[index].version += 1
        }
        await persist()
    }

    public func sync() async throws -> SyncReport<Record> {
        await loadIfNeeded()
        var rejected: [Record] = []

        // 1 · Push upserts (batch; isolate rejections).
        let upserts = entries.filter { $0.state == .pendingUpsert }.map { (id: $0.record.id, version: $0.version, record: $0.record) }
        if !upserts.isEmpty {
            do {
                try await remote.upsert(upserts.map(\.record))
                markPushed(upserts.map { ($0.id, $0.version) })
            } catch where Self.isRejection(error) {
                for upsert in upserts {
                    do {
                        try await remote.upsert([upsert.record])
                        markPushed([(upsert.id, upsert.version)])
                    } catch where Self.isRejection(error) {
                        Log.network
                            .error(
                                "Server rejected \(String(describing: upsert.id), privacy: .public): \(String(describing: error), privacy: .public)"
                            )
                        rejected.append(upsert.record)
                        entries.removeAll { $0.record.id == upsert.id }
                    }
                }
            }
            await persist()
        }

        // 2 · Push deletes.
        let deletes = entries.filter { $0.state == .pendingDelete }.map { (id: $0.record.id, version: $0.version) }
        if !deletes.isEmpty {
            try await remote.delete(deletes.map(\.id))
            for delete in deletes {
                entries.removeAll { $0.record.id == delete.id && $0.version == delete.version }
            }
            await persist()
        }

        // 3 · Pull + reconcile (server is the source of truth for everything not pending).
        let server = try await remote.fetchAll()
        reconcile(with: server)
        await persist()

        return SyncReport(records: entries.filter { $0.state != .pendingDelete }.map(\.record), rejected: rejected)
    }

    // MARK: Private

    private func reconcile(with server: [Record]) {
        let serverByID = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [Entry] = []
        var seen = Set<Record.ID>()

        for entry in entries {
            seen.insert(entry.record.id)
            switch entry.state {
            case .synced:
                if let fresh = serverByID[entry.record.id] {
                    merged.append(Entry(record: fresh, state: .synced, version: entry.version, existsRemotely: true))
                } // else: deleted on another device.
            case .pendingUpsert, .pendingDelete:
                var kept = entry
                kept.existsRemotely = kept.existsRemotely || serverByID[entry.record.id] != nil
                merged.append(kept)
            }
        }

        let added = server.filter { !seen.contains($0.id) }.map { Entry(record: $0, state: .synced, version: 0, existsRemotely: true) }
        entries = newestFirst ? added + merged : merged + added
    }

    private func markPushed(_ pushed: [(Record.ID, Int)]) {
        for (id, version) in pushed {
            guard let index = index(of: id) else { continue }
            entries[index].existsRemotely = true
            if entries[index].version == version, entries[index].state == .pendingUpsert {
                entries[index].state = .synced
            }
        }
    }

    private func index(of id: Record.ID) -> Int? {
        entries.firstIndex { $0.record.id == id }
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let stored = await store.load() ?? []
        if !isLoaded { // reentrancy: another call may have loaded while we awaited
            entries = stored
            isLoaded = true
        }
    }

    private func persist() async {
        do {
            try await store.save(entries)
        } catch {
            Log.persistence.error("Synced collection save failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func isRejection(_ error: any Error) -> Bool {
        (error as? APIError)?.isClientRejection ?? false
    }
}

/// Remote for builds without a backend: sync never runs (the gate reports `.localOnly`), but if
/// called it's a no-op that returns the local truth.
public struct LocalOnlyRemote<Record: Identifiable & Sendable>: RemoteCollection where Record.ID: Sendable {
    public init() {}
    public func fetchAll() async throws -> [Record] {
        throw CancellationError()
    }

    public func upsert(_: [Record]) async throws {}
    public func delete(_: [Record.ID]) async throws {}
}
