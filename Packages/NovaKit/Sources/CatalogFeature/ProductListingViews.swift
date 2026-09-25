import DesignSystem
import Domain
import NovaCore
import ProductUI
import Routing
import SwiftUI

/// Generic listing screen used for "See All", search results and categories.
public struct ProductListingView<Header: View>: View {
    @State private var viewModel: ProductListingViewModel
    @State private var isFilterPresented = false
    @State private var isSortPresented = false
    private let title: String
    private let showsStyleChips: [String]
    private let header: Header

    public init(
        title: String,
        styles: [String] = [],
        viewModel: @autoclosure @escaping () -> ProductListingViewModel,
        @ViewBuilder header: () -> Header
    ) {
        self.title = title
        showsStyleChips = styles
        self.header = header()
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if !showsStyleChips.isEmpty {
                    StyleChips(styles: showsStyleChips, selected: viewModel.query.styles.first) { viewModel.setStyle($0) }
                }
                ListingToolbar(
                    resultCount: viewModel.state.value?.count,
                    activeFilters: viewModel.query.activeFilterCount,
                    sort: viewModel.query.sort,
                    onSort: { isSortPresented = true },
                    onFilter: { isFilterPresented = true }
                )
                .padding(.horizontal, Spacing.screen)

                content.padding(.horizontal, Spacing.screen)
            }
            .padding(.vertical, Spacing.md)
        }
        .novaScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CartToolbarButton() } }
        .task(id: viewModel.query) { await viewModel.load() }
        .sheet(isPresented: $isFilterPresented) {
            FilterSheet(
                initial: viewModel.query,
                categories: viewModel.categories,
                priceBounds: viewModel.priceBounds,
                resultCount: viewModel.resultCount(for:)
            ) { viewModel.query = $0 }
        }
        .sheet(isPresented: $isSortPresented) {
            SortSheet(selection: Binding(get: { viewModel.query.sort }, set: { viewModel.query.sort = $0 }))
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProductGridSkeleton()
        case let .loaded(products) where products.isEmpty:
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No matches",
                message: "Try removing a filter or searching for something else.",
                actionTitle: viewModel.query.activeFilterCount > 0 ? "Clear Filters" : nil
            ) { viewModel.query = viewModel.query.resettingFilters() }
                .frame(minHeight: 360)
        case let .loaded(products):
            ProductGrid(products: products)
        case let .failed(error):
            ErrorStateView(error) { Task { await viewModel.load() } }.frame(minHeight: 360)
        }
    }
}

public extension ProductListingView where Header == EmptyView {
    init(title: String, styles: [String] = [], viewModel: @autoclosure @escaping () -> ProductListingViewModel) {
        self.init(title: title, styles: styles, viewModel: viewModel()) { EmptyView() }
    }
}

struct StyleChips: View {
    let styles: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                Chip("All", isSelected: selected == nil) { onSelect(nil) }
                ForEach(styles, id: \.self) { style in
                    Chip(style, isSelected: selected == style) { onSelect(style) }
                }
            }
            .padding(.horizontal, Spacing.screen)
        }
        .scrollIndicators(.hidden)
    }
}

struct ListingToolbar: View {
    let resultCount: Int?
    let activeFilters: Int
    let sort: SortOption
    let onSort: () -> Void
    let onFilter: () -> Void

    var body: some View {
        HStack {
            Group {
                if let resultCount {
                    Text("\(resultCount) results")
                } else {
                    Text("Loading…")
                }
            }
            .font(NovaFont.caption)
            .foregroundStyle(NovaColor.textSecondary)
            .contentTransition(.numericText())
            Spacer()
            toolbarButton(title: "Sort", systemImage: "arrow.up.arrow.down", action: onSort)
                .accessibilityValue(sort.title)
                .accessibilityIdentifier("listing.sort")
            toolbarButton(
                title: activeFilters > 0 ? "Filter (\(activeFilters))" : "Filter",
                systemImage: "slider.horizontal.3",
                action: onFilter
            )
            .accessibilityIdentifier("listing.filter")
        }
    }

    private func toolbarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(NovaFont.caption.weight(.medium))
                .foregroundStyle(NovaColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 34)
                .background(NovaColor.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(NovaColor.border) }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

// MARK: - Category

public struct CategoryView: View {
    let category: ProductCategory
    let makeViewModel: () -> ProductListingViewModel

    public init(category: ProductCategory, viewModel: @autoclosure @escaping () -> ProductListingViewModel) {
        self.category = category
        makeViewModel = viewModel
    }

    public var body: some View {
        ProductListingView(title: category.name, styles: category.styles, viewModel: makeViewModel())
    }
}

// MARK: - Collection

public struct CollectionView: View {
    let collection: EditorialCollection
    let makeViewModel: () -> ProductListingViewModel

    public init(collection: EditorialCollection, viewModel: @autoclosure @escaping () -> ProductListingViewModel) {
        self.collection = collection
        makeViewModel = viewModel
    }

    public var body: some View {
        ProductListingView(title: collection.title, viewModel: makeViewModel()) {
            CollectionHeader(collection: collection)
        }
    }
}

struct CollectionHeader: View {
    let collection: EditorialCollection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(collection.heroImageURL)
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(collection.eyebrow).font(NovaFont.eyebrow).tracking(1.5)
                    Text(collection.title).font(NovaFont.display)
                    Text(collection.subtitle).font(NovaFont.body)
                }
                .foregroundStyle(.white)
                .padding(Spacing.xl)
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: Spacing.lg) {
                if let first = collection.editorialImageURLs.first {
                    RemoteImage(first)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if collection.editorialImageURLs.count > 1 {
                        RemoteImage(collection.editorialImageURLs[1])
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    Text(collection.storyTitle).font(NovaFont.title3).foregroundStyle(NovaColor.textPrimary)
                    Text(collection.storyBody).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
    }
}

// MARK: - Shop tab

@MainActor
@Observable
public final class ShopViewModel {
    public private(set) var state: LoadState<(categories: [ProductCategory], collections: [EditorialCollection])> = .idle
    @ObservationIgnored private let catalog: any CatalogRepository

    public init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    public func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            async let categories = catalog.categories()
            async let collections = catalog.collections()
            state = try await .loaded((categories, collections))
        } catch is CancellationError {
        } catch {
            state = .failed(error.userFacing)
        }
    }
}

public struct ShopView: View {
    @State private var viewModel: ShopViewModel
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> ShopViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                VStack(spacing: Spacing.md) {
                    ForEach(0 ..< 5, id: \.self) { _ in SkeletonBlock(height: 120, radius: Radius.md) }
                }
                .padding(Spacing.screen)
                .shimmering()
            case let .loaded(content):
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(content.collections) { collection in
                        Button { router.push(.collection(collection)) } label: {
                            ShopTile(title: collection.title, subtitle: collection.subtitle, imageURL: collection.heroImageURL, height: 180)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Categories")
                        .font(NovaFont.title3)
                        .foregroundStyle(NovaColor.textPrimary)
                        .padding(.top, Spacing.lg)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(content.categories) { category in
                        Button { router.push(.category(category)) } label: {
                            ShopTile(title: category.name, subtitle: nil, imageURL: category.imageURL, height: 110)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shop.category.\(category.id.rawValue)")
                    }
                }
                .padding(Spacing.screen)
            case let .failed(error):
                ErrorStateView(error) { Task { await viewModel.load() } }.frame(minHeight: 500)
            }
        }
        .novaScreenBackground()
        .navigationTitle("Shop")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CartToolbarButton() } }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

struct ShopTile: View {
    let title: String
    let subtitle: String?
    let imageURL: URL
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RemoteImage(imageURL)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.05)], startPoint: .leading, endPoint: .trailing)
                }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(NovaFont.title2)
                if let subtitle {
                    Text(subtitle).font(NovaFont.callout)
                }
            }
            .foregroundStyle(.white)
            .padding(Spacing.xl)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
