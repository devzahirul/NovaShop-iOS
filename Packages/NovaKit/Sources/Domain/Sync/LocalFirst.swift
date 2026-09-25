import Foundation
import NovaCore

// Local-first data: every user action is written to the device first (instant UI, works offline),
// and a sync pass later reconciles it with the server. Used by the cart and the wishlist.
//
// ┌─────────┐ save/remove ┌──────────────────────┐   sync()    ┌────────────┐
// │  Store  │────────────►│ LocalFirstRepository │────────────►│  Remote    │
// │ (@Main) │◄────────────│  (actor, on disk)    │◄────────────│ (REST API) │
// └─────────┘  records()  └──────────────────────┘ server rows └────────────┘

/// Per-record sync bookkeeping. State-based (dirty flags), not an operation log: ten quantity taps
/// while offline coalesce into *one* upsert of the final value, and replaying is idempotent.
public enum SyncState: String, Codable, Sendable {
    case synced
    /// Created or changed locally; the server hasn't seen this version yet.
    case pendingUpsert
    /// Deleted locally; hidden from the UI, kept until the server confirms the delete.
    case pendingDelete
}

/// Outcome of one sync pass.
public struct SyncReport<Record: Sendable>: Sendable {
    /// Visible records after reconciling with the server.
    public let records: [Record]
    /// Local changes the server permanently refused (e.g. product discontinued). Already removed locally.
    public let rejected: [Record]

    public init(records: [Record], rejected: [Record]) {
        self.records = records
        self.rejected = rejected
    }
}

/// Port implemented in `Data` by `SyncedCollection`. The store (UI state) talks only to this.
public protocol LocalFirstRepository<Record>: Sendable {
    associatedtype Record: Identifiable & Sendable where Record.ID: Sendable

    /// Visible records (pending deletes excluded), in display order.
    func records() async -> [Record]
    /// IDs with local changes the server hasn't confirmed yet (drives the "pending" badge).
    func pendingIDs() async -> Set<Record.ID>
    func save(_ record: Record) async
    func remove(_ id: Record.ID) async
    /// Sign-out: forget this account's local copy without touching the server.
    func removeAllLocally() async
    /// Sign-in: mark guest records for upload so they merge into the account.
    func prepareForMerge() async
    /// Push pending changes, pull the server state, reconcile. Throws on transient failures
    /// (the pending changes stay queued); permanent rejections come back in the report.
    func sync() async throws -> SyncReport<Record>
}

/// What the UI shows about sync (cart header, account screen).
public enum SyncStatus: Equatable, Sendable {
    /// No backend configured / not signed in: data lives on this device only.
    case localOnly
    case idle
    case syncing
    case synced(at: Date)
    /// Offline with changes waiting.
    case waitingForNetwork
    case failed(UserFacingError)

    public var isSyncing: Bool {
        self == .syncing
    }
}

/// Whether a sync may run right now (online, signed in, backend configured). Injected into stores.
public typealias SyncEligibility = @MainActor () -> Bool
