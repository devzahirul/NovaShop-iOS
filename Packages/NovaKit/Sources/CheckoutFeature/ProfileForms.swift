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

    public private(set) var hasLoaded = false

    public func load() async {
        do {
            addresses = try await profile.addresses()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.userFacing
        }
        hasLoaded = true
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
            if let error = viewModel.error, viewModel.addresses.isEmpty {
                ErrorStateView(error) { Task { await viewModel.load() } }
            } else if viewModel.addresses.isEmpty, viewModel.hasLoaded {
                EmptyStateView(systemImage: "mappin.and.ellipse", title: "No addresses", message: "Add an address for faster checkout.")
            }
        }
        .refreshable { await viewModel.load() }
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
    /// Declaration order = on-screen order, so "first invalid field" is what the user sees first.
    public enum Field: Hashable, CaseIterable { case name, line1, city, state, postalCode }

    /// Editing a field clears its error immediately — stale red text after a fix reads as "still broken".
    public var fullName: String {
        didSet { errors[.name] = nil }
    }

    public var line1 = "" {
        didSet { errors[.line1] = nil }
    }

    public var line2 = ""
    public var city = "" {
        didSet { errors[.city] = nil }
    }

    public var state = "" {
        didSet { errors[.state] = nil }
    }

    public var postalCode = "" {
        didSet { errors[.postalCode] = nil }
    }

    public var isDefault = false
    public private(set) var errors: [Field: String] = [:]
    public private(set) var isSaving = false
    public private(set) var saveError: UserFacingError?
    /// Incremented on every rejected submit; the view scrolls + plays a haptic on change.
    public private(set) var failedSubmitCount = 0

    public var firstInvalidField: Field? {
        Field.allCases.first { errors[$0] != nil }
    }

    /// One-line summary for the banner, e.g. "Please choose a state." or "Please fix 2 fields."
    public var errorSummary: String? {
        switch errors.count {
        case 0: nil
        case 1: errors.values.first.map { "\($0)." }
        default: "Please fix the \(errors.count) highlighted fields."
        }
    }

    @ObservationIgnored private let profile: any ProfileRepository

    public init(profile: any ProfileRepository, prefillName: String = "") {
        self.profile = profile
        fullName = prefillName
    }

    public static let states = Validation.usStates

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
        guard !isSaving else { return false }
        saveError = nil
        guard validate() else {
            failedSubmitCount += 1
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let address = Address(
            fullName: fullName.trimmingCharacters(in: .whitespaces), line1: line1.trimmingCharacters(in: .whitespaces),
            line2: line2.trimmingCharacters(in: .whitespaces), city: city.trimmingCharacters(in: .whitespaces),
            state: state, postalCode: postalCode.trimmingCharacters(in: .whitespaces), isDefault: isDefault
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
    @State private var isStatePickerPresented = false
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: @autoclosure @escaping () -> AddAddressViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if let summary = viewModel.errorSummary {
                        InlineBanner(summary, style: .error)
                            .id("errors")
                            .accessibilityIdentifier("address.errorBanner")
                    }
                    NovaTextField(
                        "Full Name",
                        text: $viewModel.fullName,
                        error: viewModel.errors[.name],
                        contentType: .name,
                        autocapitalization: .words
                    )
                    .accessibilityIdentifier("address.name")
                    .id(AddAddressViewModel.Field.name)
                    NovaTextField(
                        "Street Address",
                        text: $viewModel.line1,
                        error: viewModel.errors[.line1],
                        contentType: .streetAddressLine1
                    )
                    .accessibilityIdentifier("address.line1")
                    .id(AddAddressViewModel.Field.line1)
                    NovaTextField("Apartment, suite (optional)", text: $viewModel.line2, contentType: .streetAddressLine2)
                    NovaTextField(
                        "City",
                        text: $viewModel.city,
                        error: viewModel.errors[.city],
                        contentType: .addressCity,
                        autocapitalization: .words
                    )
                    .accessibilityIdentifier("address.city")
                    .id(AddAddressViewModel.Field.city)
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Button {
                                dismissKeyboard()
                                isStatePickerPresented = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("State").font(NovaFont.caption).foregroundStyle(NovaColor.textSecondary)
                                        Text(USState.named(viewModel.state)?.name ?? "Select")
                                            .font(NovaFont.body)
                                            .lineLimit(1)
                                            .foregroundStyle(viewModel.state.isEmpty ? NovaColor.textTertiary : NovaColor.textPrimary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(NovaColor.textSecondary)
                                }
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: 56)
                                .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.sm)
                                        .strokeBorder(viewModel.errors[.state] == nil ? NovaColor.border : NovaColor.error)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("State")
                            .accessibilityValue(USState.named(viewModel.state)?.name ?? "Not selected")
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
                    .id(AddAddressViewModel.Field.state) // state + ZIP share a row
                    ToggleRow("Set as default address", isOn: $viewModel.isDefault)
                    if let error = viewModel.saveError {
                        InlineBanner(error.message, style: .error)
                    }
                    // In the scroll content, not a floating bar: a bar lifted above the keyboard covers
                    // the fields below the one being edited, so taps meant for them hit "Save" instead.
                    NovaButton("Save Address", isLoading: viewModel.isSaving) {
                        dismissKeyboard()
                        Task {
                            if await viewModel.save() {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("address.save")
                    .padding(.top, Spacing.sm)
                }
                .padding(Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .novaScreenBackground()
            .navigationTitle("Add Address")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .sheet(isPresented: $isStatePickerPresented) {
                StatePickerSheet(selection: $viewModel.state)
            }
            .sensoryFeedback(.error, trigger: viewModel.failedSubmitCount)
            .onChange(of: viewModel.failedSubmitCount) {
                // A rejected submit must be *visible*: drop the keyboard and bring the first problem into view.
                dismissKeyboard()
                let target = viewModel.firstInvalidField.map { AnyHashable($0) } ?? AnyHashable("errors")
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }
}

/// Searchable list of states — a 51-item menu of bare codes is slow to scan and easy to mis-tap.
struct StatePickerSheet: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(USState.search(query)) { state in
                Button {
                    selection = state.code
                    dismiss()
                } label: {
                    HStack {
                        Text(state.name).foregroundStyle(NovaColor.textPrimary)
                        Spacer()
                        Text(state.code).font(NovaFont.callout.monospaced()).foregroundStyle(NovaColor.textSecondary)
                        if state.code == selection {
                            Image(systemName: "checkmark").foregroundStyle(NovaColor.accent).fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("state.\(state.code)")
                .accessibilityAddTraits(state.code == selection ? .isSelected : [])
            }
            .listStyle(.plain)
            .overlay {
                if USState.search(query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search states")
            .navigationTitle("State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
