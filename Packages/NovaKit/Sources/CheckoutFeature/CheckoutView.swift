import DesignSystem
import Domain
import ProductUI
import Routing
import SwiftUI

/// Checkout (designs 18, 21, 23, 24). One screen with a three-step indicator; each step animates in.
public struct CheckoutView: View {
    @State private var viewModel: CheckoutViewModel
    @State private var isAddCardPresented = false
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let makeAddCardViewModel: () -> AddCardViewModel

    public init(
        viewModel: @autoclosure @escaping () -> CheckoutViewModel,
        addCardViewModel: @escaping () -> AddCardViewModel
    ) {
        _viewModel = State(wrappedValue: viewModel())
        makeAddCardViewModel = addCardViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            StepIndicator(steps: CheckoutViewModel.Step.allCases.map(\.title), current: viewModel.step.rawValue)
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.md)
            ScrollView {
                Group {
                    switch viewModel.step {
                    case .shipping: shippingStep
                    case .payment: paymentStep
                    case .review: reviewStep
                    }
                }
                .padding(Spacing.screen)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(viewModel.step)
            }
        }
        .animation(.snappy(duration: 0.3), value: viewModel.step)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .novaScreenBackground()
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if !viewModel.back() {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                .accessibilityLabel("Back")
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $isAddCardPresented) {
            NavigationStack {
                AddCardView(viewModel: makeAddCardViewModel()) {
                    isAddCardPresented = false
                    Task { await viewModel.load() }
                }
            }
        }
        .overlay {
            if viewModel.phase == .placing {
                ProcessingPaymentView().transition(.opacity)
            }
        }
        .animation(.easeInOut, value: viewModel.phase)
        .alert(
            "Payment failed",
            isPresented: Binding(
                get: {
                    if case .failed = viewModel.phase {
                        true
                    } else {
                        false
                    }
                },
                set: { _ in viewModel.dismissError() }
            ),
            presenting: {
                if case let .failed(error) = viewModel.phase {
                    error
                } else {
                    nil
                }
            }()
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .onChange(of: viewModel.placedOrder) { _, order in
            guard let order else { return }
            router.setPath([.orderConfirmation(order)], for: router.selectedTab)
        }
        .sensoryFeedback(.success, trigger: viewModel.placedOrder)
        .interactiveDismissDisabled(viewModel.phase == .placing)
    }

    // MARK: Steps

    private var shippingStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Shipping Address").font(NovaFont.headline)
                    Spacer()
                    Button("Add New") { router.push(.addAddress) }
                        .font(NovaFont.callout.weight(.medium))
                        .tint(NovaColor.accent)
                        .accessibilityIdentifier("checkout.addAddress")
                }
                if viewModel.addresses.isEmpty, viewModel.hasLoaded {
                    InlineBanner("Add a shipping address to continue.", style: .info)
                }
                ForEach(viewModel.addresses) { address in
                    SelectableRow(isSelected: viewModel.selectedAddressID == address.id) {
                        viewModel.selectedAddressID = address.id
                    } content: {
                        AddressSummary(address: address)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Delivery Method").font(NovaFont.headline)
                ForEach(ShippingOption.allCases) { option in
                    SelectableRow(isSelected: viewModel.shipping == option) {
                        viewModel.shipping = option
                    } content: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(NovaFont.body.weight(.medium))
                                Text(option.eta).font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                            }
                            Spacer()
                            Text(option.price == 0 ? "Free" : Money.format(option.price)).font(NovaFont.price)
                        }
                        .foregroundStyle(NovaColor.textPrimary)
                    }
                    .accessibilityIdentifier("checkout.shipping.\(option.rawValue)")
                }
            }
        }
    }

    private var paymentStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Payment Method").font(NovaFont.headline)
            ForEach(viewModel.paymentOptions) { method in
                SelectableRow(isSelected: viewModel.selectedPaymentID == method.id) {
                    viewModel.selectedPaymentID = method.id
                } content: {
                    PaymentMethodLabel(method: method)
                }
            }
            Button {
                isAddCardPresented = true
            } label: {
                Label("Add Credit or Debit Card", systemImage: "plus.circle")
                    .font(NovaFont.body.weight(.medium))
                    .foregroundStyle(NovaColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md).strokeBorder(
                            NovaColor.border,
                            style: StrokeStyle(lineWidth: 1, dash: [4])
                        )
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkout.addCard")
            Label("Payments are encrypted. We never store your full card number.", systemImage: "lock.fill")
                .font(NovaFont.caption)
                .foregroundStyle(NovaColor.textSecondary)
                .padding(.top, Spacing.sm)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Items (\(viewModel.items.count))").font(NovaFont.headline)
                ForEach(viewModel.items) { item in
                    HStack(spacing: Spacing.md) {
                        RemoteImage(item.product.primaryImageURL)
                            .frame(width: 56, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.product.name).font(NovaFont.body.weight(.medium))
                            Text("\(item.variantDescription) · Qty \(item.quantity)").font(NovaFont.caption)
                                .foregroundStyle(NovaColor.textSecondary)
                        }
                        Spacer()
                        Text(Money.format(item.lineTotal)).font(NovaFont.price)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .novaCard()

            if let address = viewModel.selectedAddress {
                summaryCard(title: "Ship to", step: .shipping) { AddressSummary(address: address) }
            }
            if let payment = viewModel.selectedPayment {
                summaryCard(title: "Pay with", step: .payment) { PaymentMethodLabel(method: payment) }
            }

            let breakdown = viewModel.breakdown
            VStack(spacing: Spacing.md) {
                PriceRow("Subtotal", value: Money.format(breakdown.subtotal))
                if breakdown.discount > 0 {
                    PriceRow("Discount", value: "-\(Money.format(breakdown.discount))", valueColor: NovaColor.success)
                }
                PriceRow("Shipping", value: (breakdown.shipping ?? 0) == 0 ? "Free" : Money.format(breakdown.shipping ?? 0))
                PriceRow("Tax", value: Money.format(breakdown.tax))
                Divider()
                PriceRow("Total", value: Money.format(breakdown.total), emphasis: true)
                    .accessibilityIdentifier("checkout.total")
            }
            .novaCard()
        }
    }

    private func summaryCard(title: String, step: CheckoutViewModel.Step, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title).font(NovaFont.headline)
                Spacer()
                Button("Change") { viewModel.go(to: step) }.font(NovaFont.callout).tint(NovaColor.accent)
            }
            content()
        }
        .novaCard()
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            if viewModel.step == .review {
                NovaButton("Place Order · \(Money.format(viewModel.breakdown.total))", isLoading: viewModel.phase == .placing) {
                    Task { await viewModel.placeOrder() }
                }
                .accessibilityIdentifier("checkout.placeOrder")
            } else {
                NovaButton(viewModel.step == .shipping ? "Continue to Payment" : "Review Order", systemImage: "arrow.right") {
                    viewModel.advance()
                }
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("checkout.continue")
            }
        }
        .padding(Spacing.screen)
        .background(.bar)
    }
}

// MARK: - Shared pieces

struct AddressSummary: View {
    let address: Address

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(address.fullName).font(NovaFont.body.weight(.medium)).foregroundStyle(NovaColor.textPrimary)
                if address.isDefault {
                    Text("Default")
                        .font(NovaFont.eyebrow)
                        .foregroundStyle(NovaColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NovaColor.accentMuted, in: Capsule())
                }
            }
            ForEach(address.formattedLines, id: \.self) { line in
                Text(line).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PaymentMethodLabel: View {
    let method: PaymentMethod

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(NovaColor.textPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(method.title).font(NovaFont.body.weight(.medium)).foregroundStyle(NovaColor.textPrimary)
                if case let .card(_, _, expiry, holder) = method.kind {
                    Text("\(holder) · Expires \(expiry)").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch method.kind {
        case .card: "creditcard"
        case .applePay: "apple.logo"
        case .payPal: "p.circle"
        }
    }
}

/// Design 24. Blocks interaction while the order is being placed.
struct ProcessingPaymentView: View {
    @State private var rotation = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NovaColor.background.opacity(0.97).ignoresSafeArea()
            VStack(spacing: Spacing.xl) {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(NovaColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
                    }
                VStack(spacing: Spacing.sm) {
                    Text("Processing Payment").font(NovaFont.title2)
                    Text("Please don't close the app.").font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("checkout.processing")
    }
}

// MARK: - Confirmation

public struct OrderConfirmationView: View {
    let order: Order
    @Environment(Router.self) private var router
    @State private var appeared = false

    public init(order: Order) {
        self.order = order
    }

    public var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NovaColor.onAccent)
                .frame(width: 88, height: 88)
                .background(NovaColor.accent, in: Circle())
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text("Thank you!").font(NovaFont.display)
                Text("Your order #\(order.number) has been placed.").font(NovaFont.body)
                    .accessibilityIdentifier("confirmation.orderNumber")
                Text("Arrives in \(order.shipping.eta). We'll email you updates.")
                    .font(NovaFont.callout)
                    .foregroundStyle(NovaColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            PriceRow("Total paid", value: Money.format(order.pricing.total), emphasis: true).novaCard()
            Spacer()
            VStack(spacing: Spacing.md) {
                Button("Track Order") { router.push(.order(order)) }.buttonStyle(.nova(.primary))
                Button("Continue Shopping") { router.popToRoot() }.buttonStyle(.nova(.outline))
                    .accessibilityIdentifier("confirmation.continue")
            }
        }
        .padding(Spacing.screen)
        .novaScreenBackground()
        .navigationBarBackButtonHidden()
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true } }
    }
}
