import DesignSystem
import Domain
import Routing
import SwiftUI

/// Product tile used by every grid and carousel. Reads the wishlist from the environment so the
/// heart is always in sync, and is `Equatable` so SwiftUI can skip re-diffing unchanged cells.
public struct ProductCard: View, Equatable {
    let product: Product
    let width: CGFloat?

    @Environment(Router.self) private var router

    public init(product: Product, width: CGFloat? = nil) {
        self.product = product
        self.width = width
    }

    public nonisolated static func == (lhs: ProductCard, rhs: ProductCard) -> Bool {
        lhs.product == rhs.product && lhs.width == rhs.width
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                router.push(.product(product.id, preview: product))
            } label: {
                RemoteImage(product.primaryImageURL)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .topLeading) { badge }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                WishlistButton(product: product)
            }

            Button {
                router.push(.product(product.id, preview: product))
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(product.name)
                        .font(NovaFont.callout)
                        .foregroundStyle(NovaColor.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    PriceLabel(price: product.price, compareAt: product.compareAtPrice)
                    SwatchDots(colors: product.colors)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.card.\(product.id.rawValue)")
    }

    @ViewBuilder
    private var badge: some View {
        if !product.inStock {
            Tag(text: "Sold out", style: .neutral)
        } else if product.isOnSale {
            Tag(text: "Sale", style: .accent)
        } else if product.isNew {
            Tag(text: "New", style: .light)
        }
    }
}

struct Tag: View {
    enum Style { case accent, light, neutral }
    let text: String
    let style: Style

    var body: some View {
        Text(text.uppercased())
            .font(NovaFont.eyebrow)
            .tracking(0.8)
            .foregroundStyle(style == .accent ? NovaColor.onAccent : NovaColor.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(background, in: Capsule())
            .padding(Spacing.sm)
    }

    private var background: AnyShapeStyle {
        switch style {
        case .accent: AnyShapeStyle(NovaColor.accent)
        case .light: AnyShapeStyle(.regularMaterial)
        case .neutral: AnyShapeStyle(NovaColor.surfaceMuted)
        }
    }
}

public struct PriceLabel: View {
    let price: Decimal
    let compareAt: Decimal?

    public init(price: Decimal, compareAt: Decimal? = nil) {
        self.price = price
        self.compareAt = compareAt
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(Money.format(price))
                .font(NovaFont.price)
                .foregroundStyle(compareAt != nil ? NovaColor.accent : NovaColor.textPrimary)
            if let compareAt, compareAt > price {
                Text(Money.format(compareAt))
                    .font(NovaFont.caption)
                    .strikethrough()
                    .foregroundStyle(NovaColor.textSecondary)
                    .accessibilityLabel("was \(Money.format(compareAt))")
            }
        }
    }
}

public struct SwatchDots: View {
    let colors: [ProductColor]

    public init(colors: [ProductColor]) {
        self.colors = colors
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(colors.prefix(4)) { color in
                Circle()
                    .fill(Color(hex: color.hex))
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5) }
                    .frame(width: 10, height: 10)
            }
            if colors.count > 4 {
                Text("+\(colors.count - 4)").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colors: \(colors.map(\.name).joined(separator: ", "))")
    }
}

/// Heart toggle. Owns no state — it reads and writes the shared `WishlistStore`.
public struct WishlistButton: View {
    let product: Product
    @Environment(WishlistStore.self) private var wishlist

    public init(product: Product) {
        self.product = product
    }

    public var body: some View {
        let isSaved = wishlist.contains(product.id)
        CircleIconButton(
            systemImage: isSaved ? "heart.fill" : "heart",
            accessibilityLabel: isSaved ? "Remove \(product.name) from wishlist" : "Save \(product.name) to wishlist",
            tint: isSaved ? NovaColor.accent : NovaColor.textPrimary
        ) {
            wishlist.toggle(product)
        }
        .symbolEffect(.bounce, value: isSaved)
        .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
        .accessibilityIdentifier("wishlist.toggle.\(product.id.rawValue)")
    }
}

/// Two-column product grid. `LazyVGrid` only builds visible cells; stable ids keep cell identity.
public struct ProductGrid: View {
    let products: [Product]

    public init(products: [Product]) {
        self.products = products
    }

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.lg, alignment: .top),
        GridItem(.flexible(), spacing: Spacing.lg, alignment: .top),
    ]

    public var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xl) {
            ForEach(products) { product in
                ProductCard(product: product).equatable()
            }
        }
    }
}

/// Skeleton matching `ProductGrid`'s geometry, so content swaps in without layout shift.
public struct ProductGridSkeleton: View {
    let count: Int

    public init(count: Int = 4) {
        self.count = count
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.lg), GridItem(.flexible(), spacing: Spacing.lg)], spacing: Spacing.xl) {
            ForEach(0 ..< count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: Radius.md).fill(NovaColor.surfaceMuted).aspectRatio(3 / 4, contentMode: .fit)
                    SkeletonBlock(height: 12)
                    SkeletonBlock(width: 60, height: 12)
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading products")
    }
}

/// Bag button with live badge for navigation bars.
public struct CartToolbarButton: View {
    @Environment(CartStore.self) private var cart
    @Environment(Router.self) private var router

    public init() {}

    public var body: some View {
        Button {
            router.push(.cart)
        } label: {
            Image(systemName: "bag")
                .font(.body.weight(.medium))
                .foregroundStyle(NovaColor.textPrimary)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if cart.itemCount > 0 {
                        Text("\(cart.itemCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(NovaColor.onAccent)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(NovaColor.accent, in: Capsule())
                            .offset(x: -2, y: 4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: cart.itemCount)
        }
        .accessibilityLabel(cart.itemCount == 0 ? "Bag" : "Bag, \(cart.itemCount) items")
        .accessibilityIdentifier("toolbar.cart")
    }
}
