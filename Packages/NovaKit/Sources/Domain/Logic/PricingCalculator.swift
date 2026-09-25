import Foundation

/// Money math in one pure function. `Decimal` (never `Double`) with banker's rounding to cents,
/// so 20 % of $277.00 is exactly $55.40 — the same number the server computes.
public enum PricingCalculator {
    public static let defaultTaxRate: Decimal = 0.0825

    public static func breakdown(
        items: [CartItem],
        coupon: Coupon?,
        shipping: ShippingOption?,
        taxRate: Decimal = defaultTaxRate
    ) -> PriceBreakdown {
        let subtotal = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        let discount = discount(for: coupon, subtotal: subtotal)
        let shippingCost = shipping?.price
        // Tax only once the destination (shipping step) is known.
        let tax = shipping == nil ? 0 : rounded((subtotal - discount) * taxRate)
        let total = subtotal - discount + (shippingCost ?? 0) + tax
        return PriceBreakdown(subtotal: subtotal, discount: discount, shipping: shippingCost, tax: tax, total: max(total, 0))
    }

    public static func discount(for coupon: Coupon?, subtotal: Decimal) -> Decimal {
        guard let coupon, subtotal >= coupon.minimumSubtotal else { return 0 }
        switch coupon.kind {
        case let .percentage(rate):
            return rounded(subtotal * rate)
        case let .fixedAmount(amount):
            return min(amount, subtotal)
        }
    }

    public static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .bankers)
        return result
    }
}
