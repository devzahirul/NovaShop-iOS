import Foundation
import NovaCore

/// Decides *when* local-first data syncs. The stores decide *how*.
///
/// Triggers: app launch · foreground · connectivity restored · sign-in (after merging the guest
/// cart) · each local change (debounced inside `SyncedList`) · background app refresh.
/// Gate: backend configured ∧ signed in ∧ online — otherwise the store shows why it's waiting.
@MainActor
public final class SyncCoordinator {
    private let network: NetworkMonitor
    private let session: SessionStore
    private let cart: CartStore
    private let wishlist: WishlistStore
    private let isBackendEnabled: Bool
    private var observers: [Task<Void, Never>] = []

    public init(network: NetworkMonitor, session: SessionStore, cart: CartStore, wishlist: WishlistStore, isBackendEnabled: Bool) {
        self.network = network
        self.session = session
        self.cart = cart
        self.wishlist = wishlist
        self.isBackendEnabled = isBackendEnabled
    }

    public func start() {
        let gate: @MainActor () -> SyncStatus? = { [weak self] in self?.blockingStatus() ?? .localOnly }
        cart.list.syncGate = gate
        wishlist.list.syncGate = gate

        let networkChanges = network.changes()
        let sessionEvents = session.events()
        observers = [
            Task { [weak self] in
                for await status in networkChanges where status == .online {
                    await self?.syncAll(reason: "network restored")
                }
            },
            Task { [weak self] in
                for await event in sessionEvents {
                    await self?.handle(event)
                }
            },
        ]
    }

    /// Syncs cart and wishlist concurrently (both are main-actor objects; their network and disk
    /// work runs in actors, so the two passes genuinely overlap).
    public func syncAll(reason: String) async {
        Log.network.info("Sync requested: \(reason, privacy: .public)")
        async let cartPass: Void = cart.sync()
        async let wishlistPass: Void = wishlist.sync()
        _ = await (cartPass, wishlistPass)
    }

    private func handle(_ event: SessionEvent) async {
        switch event {
        case .signedIn:
            // Guest items become the account's: upload them, then pull what the account already had.
            await cart.prepareForMerge()
            await wishlist.prepareForMerge()
            await syncAll(reason: "signed in")
        case .signedOut:
            await cart.removeAllLocally()
            await wishlist.removeAllLocally()
        }
    }

    private func blockingStatus() -> SyncStatus? {
        guard isBackendEnabled, session.isSignedIn else { return .localOnly }
        guard network.isOnline else { return .waitingForNetwork }
        return nil
    }
}
