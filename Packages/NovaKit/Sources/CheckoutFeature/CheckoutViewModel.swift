import Domain
import Foundation
import NovaCore
import Observation

@MainActor
@Observable
public final class CheckoutViewModel {
    public enum Step: Int, CaseIterable, Sendable {
        case shipping, payment, review

        public var title: String {
            switch self {
            case .shipping: "Shipping"
            case .payment: "Payment"
            case .review: "Review"
            }
        }
    }

    public enum Phase: Equatable {
        case editing
        case placing
        case failed(UserFacingError)
    }

    public private(set) var step: Step = .shipping
    public private(set) var addresses: [Address] = []
    public var selectedAddressID: Address.ID?
    public var shipping: ShippingOption = .standard
    public private(set) var savedCards: [PaymentMethod] = []
    /// Cards entered with "save for later" off: usable for this order, never persisted.
    public private(set) var oneTimeCards: [PaymentMethod] = []
    public var selectedPaymentID: PaymentMethod.ID?
    public private(set) var phase: Phase = .editing
    public private(set) var placedOrder: Order?
    public private(set) var hasLoaded = false
    /// Addresses / cards couldn't be loaded (e.g. offline with nothing cached).
    public private(set) var loadError: UserFacingError?

    @ObservationIgnored private let cart: CartStore
    @ObservationIgnored private let profile: any ProfileRepository
    @ObservationIgnored private let orders: any OrderService
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    /// One key per checkout attempt, reused if the user retries after a failure/timeout, so the
    /// server can deduplicate. Rotated only after an order succeeds.
    @ObservationIgnored private var idempotencyKey = UUID()

    public init(
        cart: CartStore,
        profile: any ProfileRepository,
        orders: any OrderService,
        isOnline: @escaping @MainActor () -> Bool = { true }
    ) {
        self.cart = cart
        self.profile = profile
        self.orders = orders
        self.isOnline = isOnline
    }

    /// Checkout is a server transaction; it's not offered offline (the bag itself works offline).
    public var isOffline: Bool {
        !isOnline()
    }

    // MARK: Derived

    public var items: [CartItem] {
        cart.items
    }

    public var breakdown: PriceBreakdown {
        cart.breakdown(shipping: shipping)
    }

    public var selectedAddress: Address? {
        addresses.first { $0.id == selectedAddressID }
    }

    public var paymentOptions: [PaymentMethod] {
        oneTimeCards + savedCards + [.applePay, .payPal]
    }

    public var selectedPayment: PaymentMethod? {
        paymentOptions.first { $0.id == selectedPaymentID }
    }

    public var canContinue: Bool {
        switch step {
        case .shipping: selectedAddress != nil
        case .payment: selectedPayment != nil
        case .review: !cart.isEmpty && phase != .placing
        }
    }

    // MARK: Intents

    /// Re-runs whenever the screen appears (e.g. back from "Add Address"), preserving selection and
    /// auto-selecting anything newly added.
    public func load() async {
        let previousAddressIDs = Set(addresses.map(\.id))
        let previousCardIDs = Set(savedCards.map(\.id))
        do {
            async let loadedAddresses = profile.addresses()
            async let loadedCards = profile.paymentMethods()
            (addresses, savedCards) = try await (loadedAddresses, loadedCards)
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.userFacing
        }

        if let added = addresses.first(where: { !previousAddressIDs.contains($0.id) }), hasLoaded {
            selectedAddressID = added.id
        } else if selectedAddress == nil {
            selectedAddressID = (addresses.first(where: \.isDefault) ?? addresses.first)?.id
        }
        if let added = savedCards.first(where: { !previousCardIDs.contains($0.id) }), hasLoaded {
            selectedPaymentID = added.id
        } else if selectedPayment == nil {
            selectedPaymentID = paymentOptions.first?.id
        }
        hasLoaded = true
    }

    /// Called when the add-card sheet finishes. Selects the card immediately (no reload round-trip),
    /// and keeps it for this order even if the shopper chose not to save it.
    public func useCard(_ card: PaymentMethod) {
        if !savedCards.contains(card) {
            oneTimeCards.removeAll { $0.id == card.id }
            oneTimeCards.insert(card, at: 0)
        }
        selectedPaymentID = card.id
        Task { await load() }
    }

    public func advance() {
        guard canContinue, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// Returns `false` when already on the first step (the view then pops the screen).
    public func back() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        step = previous
        return true
    }

    public func go(to step: Step) {
        guard step.rawValue < self.step.rawValue else { return }
        self.step = step
    }

    public func placeOrder() async {
        guard let address = selectedAddress, let payment = selectedPayment, !cart.isEmpty, phase != .placing else { return }
        guard isOnline() else {
            phase = .failed(CheckoutError.offline.userFacing)
            return
        }
        phase = .placing
        do {
            // The server prices *its* copy of the cart — make sure it matches what the user sees.
            try await cart.syncForCheckout()
            let draft = OrderDraft(
                items: cart.items, address: address, payment: payment, shipping: shipping, coupon: cart.coupon,
                idempotencyKey: idempotencyKey
            )
            let order = try await orders.placeOrder(draft)
            cart.completeOrder(draft.items)
            idempotencyKey = UUID()
            placedOrder = order
            phase = .editing
        } catch {
            if case .outOfStock = error as? CheckoutError {
                await cart.sync() // pull the server's view so the bag reflects what's actually available
            }
            phase = .failed(error.userFacing)
        }
    }

    public func dismissError() {
        phase = .editing
    }
}
