import DesignSystem
import Domain
import NovaCore
import ProductUI
import Routing
import SwiftUI

public struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> HomeViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                HomeSkeleton()
            case let .loaded(content):
                HomeContentView(content: content)
                    .onAppear { LaunchTimeline.shared.markContentReady() }
            case let .failed(error):
                ErrorStateView(error) { Task { await viewModel.load() } }
                    .frame(minHeight: 500)
            }
        }
        .scrollIndicators(.hidden)
        .novaScreenBackground()
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .navigationTitle("NovaShop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NovaShop").font(NovaFont.wordmark).foregroundStyle(NovaColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    router.select(.search)
                } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(NovaColor.textPrimary)
                }
                .accessibilityLabel("Search")
                CartToolbarButton()
            }
        }
    }
}

private struct HomeContentView: View {
    let content: HomeViewModel.Content
    @Environment(Router.self) private var router

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xxl) {
            if let hero = content.hero {
                HeroBanner(collection: hero) { router.push(.collection(hero)) }
            }

            CategoryStrip(categories: content.categories)

            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader("New Arrivals", actionTitle: "See All") {
                    router.push(.productList(title: "New Arrivals", query: ProductQuery(tag: ProductTag.new, sort: .newest)))
                }
                .padding(.horizontal, Spacing.screen)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Spacing.lg) {
                        ForEach(content.newArrivals) { product in
                            ProductCard(product: product, width: 150).equatable()
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.screen)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }

            if let featured = content.featured {
                EditorialBanner(collection: featured) { router.push(.collection(featured)) }
                    .padding(.horizontal, Spacing.screen)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                SectionHeader("Best Sellers", actionTitle: "See All") {
                    router.push(.productList(title: "Best Sellers", query: ProductQuery(sort: .bestSelling)))
                }
                ProductGrid(products: content.bestSellers)
            }
            .padding(.horizontal, Spacing.screen)
        }
        .padding(.bottom, Spacing.xxl)
    }
}

// MARK: - Sections

struct HeroBanner: View {
    let collection: EditorialCollection
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RemoteImage(collection.heroImageURL)
                .overlay {
                    LinearGradient(
                        colors: [NovaColor.background.opacity(0.95), NovaColor.background.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                }

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(collection.eyebrow)
                    .font(NovaFont.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(NovaColor.textSecondary)
                Text(collection.title)
                    .font(NovaFont.display)
                    .foregroundStyle(NovaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(collection.subtitle)
                    .font(NovaFont.body)
                    .foregroundStyle(NovaColor.textSecondary)
                Button(action: action) {
                    HStack(spacing: Spacing.sm) {
                        Text(collection.ctaTitle)
                        Image(systemName: "arrow.right").imageScale(.small)
                    }
                }
                .buttonStyle(.nova(.primary, fullWidth: false))
                .padding(.top, Spacing.sm)
                .accessibilityIdentifier("home.hero.cta")
            }
            .frame(maxWidth: 230, alignment: .leading)
            .padding(Spacing.xl)
        }
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .padding(.horizontal, Spacing.screen)
        .accessibilityElement(children: .contain)
    }
}

struct CategoryStrip: View {
    let categories: [ProductCategory]
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                ForEach(categories) { category in
                    Button {
                        router.push(.category(category))
                    } label: {
                        VStack(spacing: Spacing.sm) {
                            RemoteImage(category.imageURL)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                .overlay { Circle().strokeBorder(NovaColor.border, lineWidth: 0.5) }
                            Text(category.name)
                                .font(NovaFont.caption)
                                .foregroundStyle(NovaColor.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.name)
                    .accessibilityIdentifier("home.category.\(category.id.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.screen)
        }
        .scrollIndicators(.hidden)
    }
}

struct EditorialBanner: View {
    let collection: EditorialCollection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(collection.eyebrow).font(NovaFont.eyebrow).tracking(1.5).foregroundStyle(NovaColor.textSecondary)
                    Text(collection.title).font(NovaFont.title).foregroundStyle(NovaColor.textPrimary)
                    Text(collection.subtitle).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
                    HStack(spacing: Spacing.xs) {
                        Text(collection.ctaTitle)
                        Image(systemName: "arrow.right").imageScale(.small)
                    }
                    .font(NovaFont.callout.weight(.semibold))
                    .foregroundStyle(NovaColor.accent)
                    .padding(.top, Spacing.xs)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                RemoteImage(collection.heroImageURL)
                    .frame(width: 140)
            }
            .frame(height: 200)
            .background(NovaColor.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            SkeletonBlock(height: 420, radius: Radius.lg)
            HStack(spacing: Spacing.lg) {
                ForEach(0 ..< 5, id: \.self) { _ in
                    Circle().fill(NovaColor.surfaceMuted).frame(width: 64, height: 64)
                }
            }
            SkeletonBlock(width: 140, height: 20)
            HStack(spacing: Spacing.lg) {
                SkeletonBlock(width: 150, height: 200, radius: Radius.md)
                SkeletonBlock(width: 150, height: 200, radius: Radius.md)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
