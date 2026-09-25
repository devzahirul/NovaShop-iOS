import DesignSystem
import Domain
import SwiftUI

/// Filter sheet (design 09). Edits a *draft* copy of the query; nothing changes on the listing until
/// "Apply", and the button shows the live result count so users never apply into an empty page.
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProductQuery
    @State private var price: ClosedRange<Double>

    let categories: [ProductCategory]
    let priceBounds: ClosedRange<Double>
    let resultCount: (ProductQuery) -> Int
    let onApply: (ProductQuery) -> Void

    private static let colorPalette: [(name: String, hex: String)] = [
        ("Sand", "#D8C3A5"), ("Ivory", "#F4EDE2"), ("Charcoal", "#4A4A4A"), ("Black", "#1C1C1C"),
        ("Navy", "#1F2A44"), ("Crimson", "#B22234"), ("Sky", "#A9C4DE"), ("Sage", "#8A9A7B"),
    ]

    init(
        initial: ProductQuery,
        categories: [ProductCategory],
        priceBounds: ClosedRange<Decimal>,
        resultCount: @escaping (ProductQuery) -> Int,
        onApply: @escaping (ProductQuery) -> Void
    ) {
        let bounds = Double(truncating: priceBounds.lowerBound as NSNumber) ... Double(truncating: priceBounds.upperBound as NSNumber)
        _draft = State(initialValue: initial)
        _price = State(initialValue: initial.priceRange.map {
            Double(truncating: $0.lowerBound as NSNumber) ... Double(truncating: $0.upperBound as NSNumber)
        } ?? bounds)
        self.categories = categories
        self.priceBounds = bounds
        self.resultCount = resultCount
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    section("Category") {
                        FlowLayout {
                            Chip("All", isSelected: draft.categoryIDs.isEmpty) { draft.categoryIDs = [] }
                            ForEach(categories) { category in
                                Chip(category.name, isSelected: draft.categoryIDs.contains(category.id)) {
                                    draft.categoryIDs.formSymmetricDifference([category.id])
                                }
                            }
                        }
                    }
                    section("Size") {
                        FlowLayout {
                            ForEach([Size.xs, .small, .medium, .large, .xl]) { size in
                                SizeBox(size.rawValue, isSelected: draft.sizes.contains(size)) {
                                    draft.sizes.formSymmetricDifference([size])
                                }
                            }
                        }
                    }
                    section("Color") {
                        FlowLayout(spacing: Spacing.md) {
                            ForEach(Self.colorPalette, id: \.name) { color in
                                Button {
                                    draft.colorNames.formSymmetricDifference([color.name])
                                } label: {
                                    ColorSwatch(
                                        hex: color.hex,
                                        name: color.name,
                                        isSelected: draft.colorNames.contains(color.name),
                                        diameter: 30
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    section("Price Range") {
                        RangeSlider(range: $price, in: priceBounds)
                        HStack {
                            Text(Money.format(Decimal(price.lowerBound)))
                            Spacer()
                            Text(Money.format(Decimal(price.upperBound)))
                        }
                        .font(NovaFont.callout.monospacedDigit())
                        .foregroundStyle(NovaColor.textSecondary)
                    }
                    VStack(spacing: Spacing.xs) {
                        ToggleRow("On Sale Only", isOn: $draft.onSaleOnly)
                        Divider()
                        ToggleRow("In Stock Only", isOn: $draft.inStockOnly)
                    }
                }
                .padding(Spacing.screen)
            }
            .safeAreaInset(edge: .bottom) {
                let count = resultCount(resolvedDraft)
                Button("Apply Filters (\(count))") {
                    onApply(resolvedDraft)
                    dismiss()
                }
                .buttonStyle(.nova(.primary))
                .contentTransition(.numericText(value: Double(count)))
                .animation(.snappy, value: count)
                .padding(Spacing.screen)
                .background(.bar)
                .accessibilityIdentifier("filter.apply")
            }
            .novaScreenBackground()
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset") {
                        draft = draft.resettingFilters()
                        price = priceBounds
                    }
                    .tint(NovaColor.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Only store a price filter if the user actually narrowed it.
    private var resolvedDraft: ProductQuery {
        var query = draft
        query.priceRange = price == priceBounds ? nil : Decimal(price.lowerBound) ... Decimal(price.upperBound)
        return query
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title).font(NovaFont.headline).foregroundStyle(NovaColor.textPrimary).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// Sort sheet (design 10).
struct SortSheet: View {
    @Binding var selection: SortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sort By")
                .font(NovaFont.title3)
                .padding(Spacing.screen)
                .accessibilityAddTraits(.isHeader)
            ForEach(SortOption.allCases) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(option.title).font(NovaFont.body).foregroundStyle(NovaColor.textPrimary)
                        Spacer()
                        RadioIndicator(isSelected: selection == option)
                    }
                    .padding(.horizontal, Spacing.screen)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
                Divider().padding(.leading, Spacing.screen)
            }
            Spacer()
        }
        .novaScreenBackground()
        .presentationDragIndicator(.visible)
    }
}
