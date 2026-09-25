import DesignSystem
import Domain
import NovaCore
import ProductUI
import Routing
import SwiftUI

/// Cart (design 16).
public struct CartView: View {
    @Environment(CartStore.self) private var cart
    @Environment(Router.self) private var router

    public init() {}

    public var body: some View {
        Group {
            if cart.isEmpty {
                EmptyStateView(
                    systemImage: "bag",
                    title: "Your bag is empty",
                    message: "Looks like you haven't added anything yet.",
                    actionTitle: "Continue Shopping"
                ) {
                    router.popToRoot()
                    router.select(.shop)
                }
            } else {
                List {
                    Section {
                        SyncStatusRow(status: cart.syncStatus, pendingCount: cart.pendingItemIDs.count)
                        if let notice = cart.rejectionNotice {
                            InlineBanner(notice, style: .info)
                                .onTapGesture { cart.dismissRejectionNotice() }
                                .accessibilityHint("Double tap to dismiss")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    ForEach(cart.items) { item in
                        CartLineView(item: item)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(NovaColor.border)
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) { cart.remove(item.id) }
                            }
                    }
                    couponRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) { summary }
                .animation(.snappy, value: cart.items)
            }
        }
        .novaScreenBackground()
        .navigationTitle(cart.itemCount > 0 ? "My Cart (\(cart.itemCount))" : "My Cart")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cart.sync() }
    }

    private var couponRow: some View {
        Button {
            router.push(.coupon)
        } label: {
            HStack {
                Image(systemName: "tag").foregroundStyle(NovaColor.accent)
                if let coupon = cart.coupon {
                    Text("\(coupon.code) · \(coupon.headline)").foregroundStyle(NovaColor.success)
                } else {
                    Text("Add a coupon code").foregroundStyle(NovaColor.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(NovaColor.textTertiary)
            }
            .font(NovaFont.body)
            .padding(Spacing.lg)
            .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(NovaColor.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cart.coupon")
    }

    private var summary: some View {
        let breakdown = cart.breakdown(shipping: nil)
        return VStack(spacing: Spacing.md) {
            PriceRow("Subtotal", value: Money.format(breakdown.subtotal))
            if breakdown.discount > 0 {
                PriceRow("Discount", value: "-\(Money.format(breakdown.discount))", valueColor: NovaColor.success)
            }
            NovaButton("Checkout", systemImage: "arrow.right") { router.push(.checkout) }
                .accessibilityIdentifier("cart.checkout")
        }
        .padding(Spacing.screen)
        .background(.bar)
    }
}

struct CartLineView: View {
    let item: CartItem
    @Environment(CartStore.self) private var cart

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            RemoteImage(item.product.primaryImageURL)
                .frame(width: 84, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top) {
                    Text(item.product.name)
                        .font(NovaFont.body.weight(.medium))
                        .foregroundStyle(NovaColor.textPrimary)
                    Spacer()
                    Button {
                        cart.remove(item.id)
                    } label: {
                        Image(systemName: "trash").font(.footnote).foregroundStyle(NovaColor.textSecondary).frame(width: 44, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.product.name)")
                }
                Text(item.variantDescription).font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                if cart.pendingItemIDs.contains(item.id), cart.syncStatus != .localOnly {
                    Label("Not synced yet", systemImage: "icloud.and.arrow.up")
                        .font(NovaFont.caption)
                        .foregroundStyle(NovaColor.textTertiary)
                        .transition(.opacity)
                        .accessibilityIdentifier("cart.line.pending")
                }
                Spacer(minLength: Spacing.sm)
                HStack {
                    Text(Money.format(item.lineTotal)).font(NovaFont.price).foregroundStyle(NovaColor.textPrimary)
                        .contentTransition(.numericText())
                    Spacer()
                    QuantityStepper(value: Binding(
                        get: { item.quantity },
                        set: { cart.setQuantity($0, for: item.id) }
                    ), range: 1 ... CartStore.maxQuantityPerLine)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cart.line.\(item.product.id.rawValue)")
    }
}

/// One quiet line under the title: where the bag lives and whether it's up to date.
struct SyncStatusRow: View {
    let status: SyncStatus
    let pendingCount: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            icon
            Text(text)
                .font(NovaFont.caption)
                .foregroundStyle(NovaColor.textSecondary)
            Spacer()
        }
        .animation(.snappy, value: status)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.syncStatus")
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .syncing:
            ProgressView().controlSize(.mini)
        case .synced, .idle:
            Image(systemName: "checkmark.icloud").foregroundStyle(NovaColor.success)
        case .waitingForNetwork:
            Image(systemName: "icloud.slash").foregroundStyle(NovaColor.textTertiary)
        case .failed:
            Image(systemName: "exclamationmark.icloud").foregroundStyle(NovaColor.error)
        case .localOnly:
            Image(systemName: "iphone").foregroundStyle(NovaColor.textTertiary)
        }
    }

    private var text: String {
        switch status {
        case .syncing: "Syncing your bag…"
        case let .synced(date): "Synced \(date.formatted(.relative(presentation: .named)))"
        case .idle: "Your bag is up to date"
        case .waitingForNetwork: pendingCount > 0 ? "Saved on this device · will sync when you're online" : "You're offline"
        case .failed: "Couldn't sync right now · we'll retry automatically"
        case .localOnly: "Saved on this device · sign in to sync across devices"
        }
    }
}

// MARK: - Coupon (design 17)

@MainActor
@Observable
public final class CouponViewModel {
    public var code = ""
    public private(set) var isApplying = false
    public private(set) var error: UserFacingError?
    @ObservationIgnored private let cart: CartStore

    public init(cart: CartStore) {
        self.cart = cart
        code = cart.coupon?.code ?? ""
    }

    public var canApply: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty && !isApplying
    }

    public func apply() async {
        guard canApply else { return }
        isApplying = true
        error = nil
        defer { isApplying = false }
        do {
            try await cart.applyCoupon(code: code)
        } catch {
            self.error = error.userFacing
        }
    }

    public func remove() {
        cart.removeCoupon()
        code = ""
    }
}

public struct CouponView: View {
    @State private var viewModel: CouponViewModel
    @Environment(CartStore.self) private var cart
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: @autoclosure @escaping () -> CouponViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        let breakdown = cart.breakdown(shipping: nil)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.md) {
                    TextField("Enter coupon code", text: $viewModel.code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(NovaFont.body.monospaced())
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 50)
                        .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(NovaColor.border) }
                        .submitLabel(.done)
                        .onSubmit { Task { await viewModel.apply() } }
                        .accessibilityIdentifier("coupon.field")
                    NovaButton("Apply", isLoading: viewModel.isApplying) { Task { await viewModel.apply() } }
                        .frame(width: 100)
                        .disabled(!viewModel.canApply)
                        .accessibilityIdentifier("coupon.apply")
                }

                if let coupon = cart.coupon {
                    InlineBanner("Coupon applied! \(coupon.headline).", style: .success)
                        .accessibilityIdentifier("coupon.success")
                } else if let error = viewModel.error {
                    InlineBanner(error.message, style: .error)
                } else {
                    Text("Try SUMMER20 or WELCOME10").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                }

                VStack(spacing: Spacing.md) {
                    PriceRow("Subtotal", value: Money.format(breakdown.subtotal))
                    PriceRow(
                        cart.coupon.map { "Discount (\($0.code))" } ?? "Discount",
                        value: breakdown.discount > 0 ? "-\(Money.format(breakdown.discount))" : Money.format(0),
                        valueColor: breakdown.discount > 0 ? NovaColor.success : NovaColor.textPrimary
                    )
                    PriceRow("Shipping", value: "Calculated at next step")
                    Divider()
                    PriceRow("Total", value: Money.format(breakdown.total), emphasis: true)
                }
                .novaCard()
                .animation(.snappy, value: breakdown)

                if cart.coupon != nil {
                    HStack(spacing: Spacing.md) {
                        Button("Remove Coupon") { viewModel.remove() }.buttonStyle(.nova(.outline))
                        Button("Done") { dismiss() }.buttonStyle(.nova(.primary))
                    }
                }
            }
            .padding(Spacing.screen)
        }
        .novaScreenBackground()
        .navigationTitle("Apply Coupon")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: cart.coupon)
    }
}
