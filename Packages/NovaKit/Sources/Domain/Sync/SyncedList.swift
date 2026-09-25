import Foundation
import NovaCore
import Observation

/// Main-actor, observable front of a `LocalFirstRepository`. Shared engine for the cart and the
/// wishlist so the tricky parts are written — and tested — once:
///
/// - **Optimistic UI.** Mutations change `records` synchronously; the disk write and the network
///   sync happen afterwards. A tap never waits on I/O.
/// - **Ordered writes.** Repository writes go through a serial queue, so rapid taps can't land
///   out of order (unstructured `Task`s are not FIFO).
/// - **Race-free reloads.** After a sync, fresh repository state is applied only if no local
///   mutation happened while we were awaiting it (revision check) — a tap mid-sync is never
///   overwritten by a stale snapshot.
/// - **Coalesced syncs.** Mutations debounce into one sync; a sync requested while one is running
///   schedules exactly one follow-up pass instead of piling up.
/// - **Backoff.** Transient failures retry after 2 s, 4 s, 8 s … capped at 60 s. Offline doesn't
///   retry on a timer at all — the network monitor triggers a sync when connectivity returns.
@MainActor
@Observable
public final class SyncedList<Record: Identifiable & Sendable> where Record.ID: Sendable {
    public private(set) var records: [Record] = [] {
        didSet { ids = Set(records.map(\.id)) }
    }

    /// O(1) membership (e.g. the wishlist heart on every visible product card).
    public private(set) var ids: Set<Record.ID> = []
    public private(set) var pendingIDs: Set<Record.ID> = []
    public private(set) var status: SyncStatus = .localOnly
    public private(set) var isHydrated = false
    /// Records the server refused during the last sync (shown once, then cleared by the UI).
    public private(set) var rejected: [Record] = []

    /// Returns `nil` when a sync may run, otherwise the status explaining why not
    /// (`.localOnly` when signed out / no backend, `.waitingForNetwork` when offline).
    @ObservationIgnored public var syncGate: @MainActor () -> SyncStatus? = { .localOnly }

    @ObservationIgnored private let repository: any LocalFirstRepository<Record>
    @ObservationIgnored private let writes = SerialTaskQueue()
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var isSyncRunning = false
    @ObservationIgnored private var needsAnotherPass = false

    public init(
        repository: any LocalFirstRepository<Record>,
        debounce: Duration = .milliseconds(600),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.repository = repository
        self.debounce = debounce
        self.clock = clock
    }

    // MARK: Lifecycle

    public func hydrate() async {
        guard !isHydrated else { return }
        await reload()
        isHydrated = true
        refreshIdleStatus()
    }

    // MARK: Mutations (optimistic)

    public func save(_ record: Record, insertAtFront: Bool = false) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else if insertAtFront {
            records.insert(record, at: 0)
        } else {
            records.append(record)
        }
        pendingIDs.insert(record.id)
        commit { repository in await repository.save(record) }
    }

    public func remove(_ id: Record.ID) {
        records.removeAll { $0.id == id }
        pendingIDs.insert(id)
        commit { repository in await repository.remove(id) }
    }

    /// Sign-out: drop this account's local copy (server untouched).
    public func removeAllLocally() async {
        revision += 1
        debounceTask?.cancel()
        retryTask?.cancel()
        records = []
        pendingIDs = []
        rejected = []
        let repository = repository
        writes.enqueue { await repository.removeAllLocally() }
        await writes.flush()
        refreshIdleStatus()
    }

    /// Sign-in: upload guest records into the account on the next sync.
    public func prepareForMerge() async {
        let repository = repository
        writes.enqueue { await repository.prepareForMerge() }
        await reload()
    }

    public func clearRejected() {
        rejected = []
    }

    // MARK: Sync

    /// Runs a sync now if allowed. Safe to call from anywhere, any number of times.
    public func sync() async {
        debounceTask?.cancel()
        if let blocked = syncGate() {
            status = pendingIDs.isEmpty && blocked == .waitingForNetwork ? .idle : blocked
            return
        }
        guard !isSyncRunning else {
            needsAnotherPass = true
            return
        }
        isSyncRunning = true
        defer { isSyncRunning = false }

        repeat {
            needsAnotherPass = false
            await runSyncPass()
        } while needsAnotherPass && syncGate() == nil
    }

    /// Waits for queued disk writes (tests, and before the app is suspended).
    public func flushWrites() async {
        await writes.flush()
    }

    // MARK: Private

    private func commit(_ write: @escaping @Sendable (any LocalFirstRepository<Record>) async -> Void) {
        revision += 1
        let repository = repository
        writes.enqueue { await write(repository) }
        scheduleSync()
    }

    private func scheduleSync() {
        debounceTask?.cancel()
        guard syncGate() == nil else {
            refreshIdleStatus()
            return
        }
        let clock = clock
        let debounce = debounce
        debounceTask = Task { [weak self] in
            do {
                try await clock.sleep(for: debounce)
            } catch {
                return // superseded by a newer mutation
            }
            await self?.sync()
        }
    }

    private func runSyncPass() async {
        status = .syncing
        await writes.flush()
        do {
            let report = try await Perf.measure("Sync.Pass") { try await repository.sync() }
            if !report.rejected.isEmpty {
                rejected = report.rejected
            }
            await reload()
            retryAttempt = 0
            retryTask?.cancel()
            status = .synced(at: .now)
        } catch is CancellationError {
            refreshIdleStatus()
        } catch {
            await reload()
            let userFacing = error.userFacing
            if userFacing == .offline {
                status = .waitingForNetwork // the network monitor re-triggers sync; no timer needed
            } else {
                status = .failed(userFacing)
                scheduleRetry()
            }
            Log.network.notice("Sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryAttempt += 1
        let seconds = min(60, 1 << min(retryAttempt, 6)) // 2, 4, 8, 16, 32, 60
        let clock = clock
        retryTask = Task { [weak self] in
            do {
                try await clock.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            await self?.sync()
        }
    }

    /// Applies repository state, retrying if a local mutation raced the read.
    private func reload() async {
        while true {
            let startRevision = revision
            await writes.flush()
            let fresh = await repository.records()
            let pending = await repository.pendingIDs()
            if startRevision == revision {
                records = fresh
                pendingIDs = pending
                return
            }
        }
    }

    private func refreshIdleStatus() {
        if let blocked = syncGate() {
            status = blocked == .waitingForNetwork && pendingIDs.isEmpty ? .idle : blocked
        } else if case .syncing = status {
            status = .idle
        } else if status == .localOnly || status == .waitingForNetwork {
            status = .idle
        }
    }
}

/// Serial async work queue (FIFO), main-actor confined. Each job starts after the previous one ends.
@MainActor
final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ job: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await job()
        }
    }

    func flush() async {
        await tail?.value
    }
}
