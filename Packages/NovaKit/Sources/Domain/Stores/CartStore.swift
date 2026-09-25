import Foundation
import NovaCore
import Observation

/// App-wide cart state, local-first.
///
/// Every change is applied instantly and persisted on device; `SyncedList` then reconciles it with
/// the server when the user is signed in and online. Offline edits coalesce and upload later; the
/// server remains the source of truth for everything already synced.
///
/// Observation (`@Observable`) tracks property access per view, so the tab badge re-renders when
/// the lines change but the product grid (which never reads them) does not.
@MainActor
@Observable
public final class CartStore {
    public private(set) var coupon: Coupon?

    @ObservationIgnored public let list: SyncedList<CartItem>
    @ObservationIgnored private let couponService: any CouponService

    public static let maxQuantityPerLine = 10

    public init(
        repository: any LocalFirstRepository<CartItem>,
        couponService: any CouponService,
        debounce: Duration = .milliseconds(600),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        list = SyncedList(repository: repository, debounce: debounce, clock: clock)
        self.couponService = couponService
    }

    // MARK: Derived

    public var items: [CartItem] {
        list.records
    }

    public var pendingItemIDs: Set<CartItem.ID> {
        list.pendingIDs
    }

    public var syncStatus: SyncStatus {
        list.status
    }

    public var isHydrated: Bool {
        list.isHydrated
    }

    public var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    /// One-line explanation after the server refused lines (e.g. a product was discontinued).
    public var rejectionNotice: String? {
        let names = list.rejected.map(\.product.name)
        guard !names.isEmpty else { return nil }
        let verb = names.count == 1 ? "is" : "are"
        return "\(ListFormatter.localizedString(byJoining: names)) \(verb) no longer available and was removed from your bag."
    }

    public func breakdown(shipping: ShippingOption?) -> PriceBreakdown {
        PricingCalculator.breakdown(items: items, coupon: coupon, shipping: shipping)
    }

    // MARK: Lifecycle

    /// Loads the on-device cart *after* first frame (never blocks launch).
    public func hydrate() async {
        await list.hydrate()
    }

    public func sync() async {
        await list.sync()
    }

    // MARK: Mutations (instant, persisted, synced later)

    public func add(_ product: Product, color: ProductColor?, size: Size?, quantity: Int = 1) {
        var line = CartItem(product: product, color: color, size: size, quantity: quantity)
        if let existing = items.first(where: { $0.id == line.id }) {
            line.quantity = min(existing.quantity + quantity, Self.maxQuantityPerLine)
        }
        list.save(line)
    }

    public func setQuantity(_ quantity: Int, for itemID: CartItem.ID) {
        guard var line = items.first(where: { $0.id == itemID }) else { return }
        if quantity <= 0 {
            list.remove(itemID)
        } else {
            line.quantity = min(quantity, Self.maxQuantityPerLine)
            list.save(line)
        }
        revalidateCoupon()
    }

    public func remove(_ itemID: CartItem.ID) {
        list.remove(itemID)
        revalidateCoupon()
    }

    /// After a successful order: the server already emptied its cart inside the checkout
    /// transaction; mirror that locally for the lines that were ordered (lines added meanwhile stay).
    public func completeOrder(_ ordered: [CartItem]) {
        for line in ordered {
            list.remove(line.id)
        }
        coupon = nil
    }

    /// Sign-out.
    public func removeAllLocally() async {
        coupon = nil
        await list.removeAllLocally()
    }

    /// Sign-in: guest lines are merged into the account's cart on the next sync.
    public func prepareForMerge() async {
        await list.prepareForMerge()
    }

    /// Checkout needs the server to hold exactly what the user sees (it prices the *server* cart).
    public func syncForCheckout() async throws {
        await list.sync()
        switch list.status {
        case .waitingForNetwork:
            throw CheckoutError.offline
        case .failed:
            throw CheckoutError.cartNotSynced
        default:
            if !list.pendingIDs.isEmpty, list.syncGate() == nil {
                throw CheckoutError.cartNotSynced
            }
        }
    }

    @discardableResult
    public func applyCoupon(code: String) async throws -> Coupon {
        let subtotal = breakdown(shipping: nil).subtotal
        let coupon = try await couponService.validate(code: code, subtotal: subtotal)
        self.coupon = coupon
        return coupon
    }

    public func removeCoupon() {
        coupon = nil
    }

    public func dismissRejectionNotice() {
        list.clearRejected()
    }

    /// Test / lifecycle hook: wait for pending disk writes.
    public func flush() async {
        await list.flushWrites()
    }

    // MARK: Private

    private func revalidateCoupon() {
        if let coupon, breakdown(shipping: nil).subtotal < coupon.minimumSubtotal || items.isEmpty {
            self.coupon = nil
        }
    }
}
