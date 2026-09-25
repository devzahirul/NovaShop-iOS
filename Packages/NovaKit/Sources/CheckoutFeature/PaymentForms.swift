import DesignSystem
import Domain
import Foundation
import NovaCore
import SwiftUI

// MARK: - Add card (design 22)

@MainActor
@Observable
public final class AddCardViewModel {
    public enum Field: Hashable, CaseIterable { case number, name, expiry, cvv }

    public var number = "" {
        didSet {
            if number != CardFormatter.formatNumber(number) {
                number = CardFormatter.formatNumber(number)
            }
            errors[.number] = nil
        }
    }

    public var holder = "" {
        didSet { errors[.name] = nil }
    }

    public var expiry = "" {
        didSet {
            if expiry != CardFormatter.formatExpiry(expiry) {
                expiry = CardFormatter.formatExpiry(expiry)
            }
            errors[.expiry] = nil
        }
    }

    public var cvv = "" {
        didSet {
            if cvv.count > 4 {
                cvv = String(cvv.prefix(4))
            }
            errors[.cvv] = nil
        }
    }

    public var saveForLater = true
    public private(set) var errors: [Field: String] = [:]
    public private(set) var isSaving = false

    @ObservationIgnored private let profile: any ProfileRepository
    @ObservationIgnored private let now: () -> Date

    public init(profile: any ProfileRepository, now: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.now = now
    }

    /// Incremented on every rejected submit; the view scrolls + plays a haptic on change.
    public private(set) var failedSubmitCount = 0

    public var firstInvalidField: Field? {
        Field.allCases.first { errors[$0] != nil }
    }

    public var brand: CardBrand {
        Validation.brand(forCardNumber: number)
    }

    public var last4: String {
        String(number.filter(\.isNumber).suffix(4))
    }

    public func validate() -> Bool {
        var errors: [Field: String] = [:]
        errors[.number] = Validation.cardNumber(number)?.message
        errors[.name] = Validation.required(holder, field: "Name on card")?.message
        errors[.expiry] = Validation.expiry(expiry, now: now())?.message
        errors[.cvv] = Validation.cvv(cvv, brand: brand)?.message
        self.errors = errors
        return errors.isEmpty
    }

    /// Only a tokenised reference is kept — in production the PAN goes straight to the payment
    /// provider's SDK and never touches our storage or logs.
    public func save() async -> PaymentMethod? {
        guard !isSaving else { return nil }
        guard validate() else {
            failedSubmitCount += 1
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        let method = PaymentMethod(kind: .card(brand: brand, last4: last4, expiry: expiry, holder: holder))
        if saveForLater {
            _ = try? await profile.save(method)
        }
        return method
    }
}

public struct AddCardView: View {
    @State private var viewModel: AddCardViewModel
    private let onSaved: (PaymentMethod) -> Void
    @Environment(\.dismiss) private var dismiss

    /// `onSaved` receives the card even when "save for later" is off, so it can pay for this order.
    public init(viewModel: @autoclosure @escaping () -> AddCardViewModel, onSaved: @escaping (PaymentMethod) -> Void) {
        _viewModel = State(wrappedValue: viewModel())
        self.onSaved = onSaved
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    CardPreview(number: viewModel.number, holder: viewModel.holder, expiry: viewModel.expiry, brand: viewModel.brand)
                    NovaTextField(
                        "Card Number", text: $viewModel.number, prompt: "1234 5678 9012 3456", error: viewModel.errors[.number],
                        contentType: .creditCardNumber, keyboard: .numberPad
                    )
                    .accessibilityIdentifier("card.number")
                    .id(AddCardViewModel.Field.number)
                    NovaTextField(
                        "Name on Card",
                        text: $viewModel.holder,
                        error: viewModel.errors[.name],
                        contentType: .name,
                        autocapitalization: .words
                    )
                    .accessibilityIdentifier("card.name")
                    .id(AddCardViewModel.Field.name)
                    HStack(alignment: .top, spacing: Spacing.md) {
                        NovaTextField(
                            "Expiration Date",
                            text: $viewModel.expiry,
                            prompt: "MM/YY",
                            error: viewModel.errors[.expiry],
                            keyboard: .numberPad
                        )
                        .accessibilityIdentifier("card.expiry")
                        NovaTextField(
                            "CVV",
                            text: $viewModel.cvv,
                            prompt: "123",
                            error: viewModel.errors[.cvv],
                            isSecure: true,
                            keyboard: .numberPad
                        )
                        .accessibilityIdentifier("card.cvv")
                    }
                    .id(AddCardViewModel.Field.expiry)
                    ToggleRow("Save this card for future purchases", isOn: $viewModel.saveForLater)
                    // Part of the form (see AddAddressView): a keyboard-lifted bar would cover the fields.
                    NovaButton("Add Card", isLoading: viewModel.isSaving) {
                        dismissKeyboard()
                        Task {
                            if let method = await viewModel.save() {
                                onSaved(method)
                            }
                        }
                    }
                    .accessibilityIdentifier("card.save")
                    .padding(.top, Spacing.sm)
                }
                .padding(Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .novaScreenBackground()
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .keyboardDoneButton()
            .sensoryFeedback(.error, trigger: viewModel.failedSubmitCount)
            .onChange(of: viewModel.failedSubmitCount) {
                dismissKeyboard()
                let target = viewModel.firstInvalidField == .cvv ? .expiry : viewModel.firstInvalidField
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }
}

struct CardPreview: View {
    let number: String
    let holder: String
    let expiry: String
    let brand: CardBrand

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Image(systemName: "wave.3.right").font(.title3)
                Spacer()
                Text(brand == .unknown ? "" : brand.displayName.uppercased()).font(NovaFont.headline.italic())
            }
            Spacer()
            Text(number.isEmpty ? "•••• •••• •••• ••••" : number)
                .font(.system(.title3, design: .monospaced))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARD HOLDER").font(NovaFont.eyebrow).opacity(0.7)
                    Text(holder.isEmpty ? "YOUR NAME" : holder.uppercased()).font(NovaFont.callout)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPIRES").font(NovaFont.eyebrow).opacity(0.7)
                    Text(expiry.isEmpty ? "MM/YY" : expiry).font(NovaFont.callout.monospacedDigit())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Spacing.xl)
        .frame(height: 200)
        .background(
            LinearGradient(colors: [Color(hex: "#7A4A36"), Color(hex: "#B98166")], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Payment methods (design 21, from Account)

@MainActor
@Observable
public final class PaymentMethodsViewModel {
    public private(set) var cards: [PaymentMethod] = []
    public private(set) var error: UserFacingError?
    @ObservationIgnored private let profile: any ProfileRepository

    public init(profile: any ProfileRepository) {
        self.profile = profile
    }

    public func load() async {
        do {
            cards = try await profile.paymentMethods()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.userFacing
        }
    }
}

public struct PaymentMethodsView: View {
    @State private var viewModel: PaymentMethodsViewModel
    @State private var isAddCardPresented = false
    private let makeAddCardViewModel: () -> AddCardViewModel

    public init(viewModel: @autoclosure @escaping () -> PaymentMethodsViewModel, addCardViewModel: @escaping () -> AddCardViewModel) {
        _viewModel = State(wrappedValue: viewModel())
        makeAddCardViewModel = addCardViewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if let error = viewModel.error {
                    InlineBanner(error.message, style: .error)
                }
                ForEach(viewModel.cards + [.applePay, .payPal]) { method in
                    PaymentMethodLabel(method: method)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .novaCard()
                }
            }
            .padding(Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add Credit or Debit Card") { isAddCardPresented = true }
                .buttonStyle(.nova(.primary))
                .padding(Spacing.screen)
        }
        .novaScreenBackground()
        .navigationTitle("Payment Methods")
        .task { await viewModel.load() }
        .sheet(isPresented: $isAddCardPresented) {
            NavigationStack {
                AddCardView(viewModel: makeAddCardViewModel()) { _ in
                    isAddCardPresented = false
                    Task { await viewModel.load() }
                }
            }
        }
    }
}
