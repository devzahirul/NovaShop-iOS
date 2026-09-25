import Foundation
import NovaCore
import Observation

/// App-wide cart state. Injected into the SwiftUI environment once; every screen that shows a bag
/// badge, a cart line or a total reads the same instance, so there is exactly one source of truth.
///
/// Observation (`@Observable`) tracks property access per view, so the tab badge re-renders when
/// `items` changes but the product grid (which never reads `items`) does not.
@MainActor
@Observable
public final class CartStore {
    public private(set) var items: [CartItem] = []
    public private(set) var coupon: Coupon?
    public private(set) var isHydrated = false

    @ObservationIgnored private let saveQueue: SaveQueue<[CartItem]>
    @ObservationIgnored private let persistence: any Persisting<[CartItem]>
    @ObservationIgnored private let couponService: any CouponService

    public static let maxQuantityPerLine = 10

    public init(persistence: any Persisting<[CartItem]>, couponService: any CouponService) {
        self.persistence = persistence
        self.couponService = couponService
        saveQueue = SaveQueue(store: persistence)
    }

    // MARK: Derived

    public var itemCount: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public func breakdown(shipping: ShippingOption?) -> PriceBreakdown {
        PricingCalculator.breakdown(items: items, coupon: coupon, shipping: shipping)
    }

    // MARK: Lifecycle

    /// Loads the persisted cart *after* first frame. Anything added before hydration completes is
    /// merged on top instead of being clobbered by the disk snapshot.
    public func hydrate() async {
        guard !isHydrated else { return }
        let stored = await persistence.load() ?? []
        let addedBeforeHydration = items
        items = stored
        for line in addedBeforeHydration {
            merge(line)
        }
        isHydrated = true
        if !addedBeforeHydration.isEmpty {
            persist()
        }
    }

    // MARK: Mutations

    public func add(_ product: Product, color: ProductColor?, size: Size?, quantity: Int = 1) {
        merge(CartItem(product: product, color: color, size: size, quantity: quantity))
        persist()
    }

    public func setQuantity(_ quantity: Int, for itemID: CartItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        if quantity <= 0 {
            items.remove(at: index)
        } else {
            items[index].quantity = min(quantity, Self.maxQuantityPerLine)
        }
        revalidateCoupon()
        persist()
    }

    public func remove(_ itemID: CartItem.ID) {
        items.removeAll { $0.id == itemID }
        revalidateCoupon()
        persist()
    }

    public func clear() {
        items = []
        coupon = nil
        persist()
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

    /// Test / lifecycle hook: wait for pending disk writes.
    public func flush() async {
        await saveQueue.flush()
    }

    // MARK: Private

    private func merge(_ line: CartItem) {
        if let index = items.firstIndex(where: { $0.id == line.id }) {
            items[index].quantity = min(items[index].quantity + line.quantity, Self.maxQuantityPerLine)
        } else {
            items.append(line)
        }
    }

    private func revalidateCoupon() {
        if let coupon, breakdown(shipping: nil).subtotal < coupon.minimumSubtotal || items.isEmpty {
            self.coupon = nil
        }
    }

    private func persist() {
        saveQueue.enqueue(items)
    }
}
