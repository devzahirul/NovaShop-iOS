import DesignSystem
import Domain
import Foundation
import NovaCore
import Routing
import SwiftUI

// MARK: - Address list (design 26)

@MainActor
@Observable
public final class AddressListViewModel {
    public private(set) var addresses: [Address] = []
    public private(set) var error: UserFacingError?
    @ObservationIgnored private let profile: any ProfileRepository

    public init(profile: any ProfileRepository) {
        self.profile = profile
    }

    public func load() async {
        addresses = await profile.addresses()
    }

    public func makeDefault(_ address: Address) async {
        var updated = address
        updated.isDefault = true
        do { addresses = try await profile.save(updated) } catch { self.error = error.userFacing }
    }

    public func delete(_ address: Address) async {
        do { addresses = try await profile.deleteAddress(id: address.id) } catch { self.error = error.userFacing }
    }
}

public struct AddressListView: View {
    @State private var viewModel: AddressListViewModel
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> AddressListViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        List {
            ForEach(viewModel.addresses) { address in
                AddressSummary(address: address)
                    .padding(.vertical, Spacing.sm)
                    .listRowBackground(NovaColor.surface)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await viewModel.delete(address) } }
                        if !address.isDefault {
                            Button("Default", systemImage: "star") { Task { await viewModel.makeDefault(address) } }.tint(NovaColor.accent)
                        }
                    }
            }
        }
        .overlay {
            if viewModel.addresses.isEmpty {
                EmptyStateView(systemImage: "mappin.and.ellipse", title: "No addresses", message: "Add an address for faster checkout.")
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Add New Address") { router.push(.addAddress) }
                .buttonStyle(.nova(.primary))
                .padding(Spacing.screen)
        }
        .novaScreenBackground()
        .navigationTitle("Addresses")
        .task { await viewModel.load() }
    }
}

// MARK: - Add address (design 20)

@MainActor
@Observable
public final class AddAddressViewModel {
    public enum Field: Hashable { case name, line1, city, state, postalCode }

    public var fullName: String
    public var line1 = ""
    public var line2 = ""
    public var city = ""
    public var state = ""
    public var postalCode = ""
    public var isDefault = false
    public private(set) var errors: [Field: String] = [:]
    public private(set) var isSaving = false
    public private(set) var saveError: UserFacingError?

    @ObservationIgnored private let profile: any ProfileRepository

    public init(profile: any ProfileRepository, prefillName: String = "") {
        self.profile = profile
        fullName = prefillName
    }

    public static let states = ["AL", "AK", "AZ", "CA", "CO", "CT", "FL", "GA", "IL", "MA", "NY", "OR", "TX", "WA"]

    /// Validates every field and returns whether the form is valid. Errors appear only after submit.
    public func validate() -> Bool {
        var errors: [Field: String] = [:]
        errors[.name] = Validation.required(fullName, field: "Full name")?.message
        errors[.line1] = Validation.required(line1, field: "Street address")?.message
        errors[.city] = Validation.required(city, field: "City")?.message
        errors[.state] = Validation.required(state, field: "State")?.message
        errors[.postalCode] = Validation.postalCode(postalCode)?.message
        self.errors = errors
        return errors.isEmpty
    }

    public func save() async -> Bool {
        guard validate() else { return false }
        isSaving = true
        defer { isSaving = false }
        let address = Address(
            fullName: fullName.trimmingCharacters(in: .whitespaces), line1: line1, line2: line2, city: city,
            state: state, postalCode: postalCode, isDefault: isDefault
        )
        do {
            _ = try await profile.save(address)
            return true
        } catch {
            saveError = error.userFacing
            return false
        }
    }
}

public struct AddAddressView: View {
    @State private var viewModel: AddAddressViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: @autoclosure @escaping () -> AddAddressViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                NovaTextField(
                    "Full Name",
                    text: $viewModel.fullName,
                    error: viewModel.errors[.name],
                    contentType: .name,
                    autocapitalization: .words
                )
                .accessibilityIdentifier("address.name")
                NovaTextField("Street Address", text: $viewModel.line1, error: viewModel.errors[.line1], contentType: .streetAddressLine1)
                    .accessibilityIdentifier("address.line1")
                NovaTextField("Apartment, suite (optional)", text: $viewModel.line2, contentType: .streetAddressLine2)
                NovaTextField(
                    "City",
                    text: $viewModel.city,
                    error: viewModel.errors[.city],
                    contentType: .addressCity,
                    autocapitalization: .words
                )
                .accessibilityIdentifier("address.city")
                HStack(alignment: .top, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Menu {
                            Picker("State", selection: $viewModel.state) {
                                ForEach(AddAddressViewModel.states, id: \.self) { Text($0).tag($0) }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("State").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                                    Text(viewModel.state.isEmpty ? "Select" : viewModel.state).font(NovaFont.body)
                                        .foregroundStyle(viewModel.state.isEmpty ? NovaColor.textTertiary : NovaColor.textPrimary)
                                }
                                Spacer()
                                Image(systemName: "chevron.down").font(.caption).foregroundStyle(NovaColor.textSecondary)
                            }
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: 56)
                            .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .strokeBorder(viewModel.errors[.state] == nil ? NovaColor.border : NovaColor.error)
                            }
                        }
                        .accessibilityIdentifier("address.state")
                        if let error = viewModel.errors[.state] {
                            Text(error).font(NovaFont.caption).foregroundStyle(NovaColor.error)
                        }
                    }
                    NovaTextField(
                        "ZIP Code", text: $viewModel.postalCode, error: viewModel.errors[.postalCode],
                        contentType: .postalCode, keyboard: .numberPad
                    )
                    .accessibilityIdentifier("address.zip")
                }
                ToggleRow("Set as default address", isOn: $viewModel.isDefault)
                if let error = viewModel.saveError {
                    InlineBanner(error.message, style: .error)
                }
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            NovaButton("Save Address", isLoading: viewModel.isSaving) {
                Task {
                    if await viewModel.save() {
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("address.save")
            .padding(Spacing.screen)
            .background(.bar)
        }
        .novaScreenBackground()
        .navigationTitle("Add Address")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add card (design 22)

@MainActor
@Observable
public final class AddCardViewModel {
    public enum Field: Hashable { case number, name, expiry, cvv }

    public var number = "" {
        didSet {
            if number != CardFormatter.formatNumber(number) {
                number = CardFormatter.formatNumber(number)
            }
        }
    }

    public var holder = ""
    public var expiry = "" {
        didSet {
            if expiry != CardFormatter.formatExpiry(expiry) {
                expiry = CardFormatter.formatExpiry(expiry)
            }
        }
    }

    public var cvv = "" {
        didSet {
            if cvv.count > 4 {
                cvv = String(cvv.prefix(4))
            }
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
        guard validate() else { return nil }
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
    private let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: @autoclosure @escaping () -> AddCardViewModel, onSaved: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel())
        self.onSaved = onSaved
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                CardPreview(number: viewModel.number, holder: viewModel.holder, expiry: viewModel.expiry, brand: viewModel.brand)
                NovaTextField(
                    "Card Number", text: $viewModel.number, prompt: "1234 5678 9012 3456", error: viewModel.errors[.number],
                    contentType: .creditCardNumber, keyboard: .numberPad
                )
                .accessibilityIdentifier("card.number")
                NovaTextField(
                    "Name on Card",
                    text: $viewModel.holder,
                    error: viewModel.errors[.name],
                    contentType: .name,
                    autocapitalization: .words
                )
                .accessibilityIdentifier("card.name")
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
                ToggleRow("Save this card for future purchases", isOn: $viewModel.saveForLater)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            NovaButton("Add Card", isLoading: viewModel.isSaving) {
                Task {
                    if await viewModel.save() != nil {
                        onSaved()
                    }
                }
            }
            .accessibilityIdentifier("card.save")
            .padding(Spacing.screen)
            .background(.bar)
        }
        .novaScreenBackground()
        .navigationTitle("Add Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
    @ObservationIgnored private let profile: any ProfileRepository

    public init(profile: any ProfileRepository) {
        self.profile = profile
    }

    public func load() async {
        cards = await profile.paymentMethods()
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
                AddCardView(viewModel: makeAddCardViewModel()) {
                    isAddCardPresented = false
                    Task { await viewModel.load() }
                }
            }
        }
    }
}
