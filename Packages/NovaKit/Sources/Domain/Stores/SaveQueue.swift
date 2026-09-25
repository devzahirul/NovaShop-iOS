import NovaCore

/// Serialises writes to a `Persisting` store.
///
/// Firing `Task { try await store.save(value) }` per mutation looks fine but is a real bug:
/// unstructured tasks are not FIFO, so a rapid "add, add, remove" can persist the *second* snapshot
/// last and resurrect a deleted item on next launch. Chaining each write onto the previous one
/// guarantees last-write-wins while still keeping disk I/O off the main actor.
@MainActor
final class SaveQueue<Value: Sendable> {
    private let store: any Persisting<Value>
    private var tail: Task<Void, Never>?

    init(store: any Persisting<Value>) {
        self.store = store
    }

    func enqueue(_ value: Value) {
        let previous = tail
        let store = store
        tail = Task(priority: .utility) {
            await previous?.value
            do {
                try await store.save(value)
            } catch {
                Log.persistence.error("Save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Awaits all pending writes. Used by tests and before the app is suspended.
    func flush() async {
        await tail?.value
    }
}
