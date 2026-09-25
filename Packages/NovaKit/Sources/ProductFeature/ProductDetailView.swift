import DesignSystem
import Domain
import ProductUI
import Routing
import SwiftUI

/// Product detail (design 11).
public struct ProductDetailView: View {
    @State private var viewModel: ProductDetailViewModel
    @State private var galleryIndex: Int?
    @State private var isSizeGuidePresented = false
    @State private var toast: String?
    @State private var addedCount = 0
    @State private var sizeErrorCount = 0
    @Environment(Router.self) private var router

    public init(viewModel: @autoclosure @escaping () -> ProductDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel())
    }

    public var body: some View {
        Group {
            switch viewModel.product {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ErrorStateView(error) { Task { await viewModel.load() } }
            case let .loaded(product):
                content(product)
            }
        }
        .novaScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CartToolbarButton() } }
        .task { await viewModel.load() }
        .toast($toast)
        .sensoryFeedback(.success, trigger: addedCount)
        .sensoryFeedback(.error, trigger: sizeErrorCount)
    }

    private func content(_ product: Product) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    ImagePager(product: product) { galleryIndex = $0 }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        header(product)
                        if !product.colors.isEmpty {
                            colorPicker(product)
                        }
                        sizePicker(product).id(Self.sizePickerID)
                        details(product)
                        reviewsTeaser(product)
                    }
                    .padding(.horizontal, Spacing.screen)

                    if !viewModel.related.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            SectionHeader("You May Also Like").padding(.horizontal, Spacing.screen)
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: Spacing.lg) {
                                    ForEach(viewModel.related) { ProductCard(product: $0, width: 140).equatable() }
                                }
                                .padding(.horizontal, Spacing.screen)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) { addToCartBar(product) }
            .fullScreenCover(item: Binding(
                get: { galleryIndex.map(GalleryItem.init) },
                set: { galleryIndex = $0?.index }
            )) { item in
                ImageGalleryView(imageURLs: product.imageURLs, startIndex: item.index)
            }
            .sheet(isPresented: $isSizeGuidePresented) { SizeGuideView() }
            // Missing size → bring the picker (and its error) into view instead of failing silently
            // below the fold under the sticky button.
            .onChange(of: sizeErrorCount) {
                withAnimation(.snappy) { proxy.scrollTo(Self.sizePickerID, anchor: .center) }
            }
        }
    }

    private static let sizePickerID = "product.sizes"

    private func header(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(product.name)
                .font(NovaFont.title)
                .foregroundStyle(NovaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("product.title")
            PriceLabel(price: product.price, compareAt: product.compareAtPrice)
                .font(NovaFont.title3)
            Button {
                router.push(.reviews(product))
            } label: {
                RatingView(rating: product.rating, count: product.reviewCount, starSize: .caption)
            }
            .buttonStyle(.plain)
        }
    }

    private func colorPicker(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            (Text("Color: ").foregroundStyle(NovaColor.textSecondary) + Text(viewModel.selectedColor?.name ?? ""))
                .font(NovaFont.callout)
            HStack(spacing: Spacing.sm) {
                ForEach(product.colors) { color in
                    Button {
                        viewModel.selectedColor = color
                    } label: {
                        ColorSwatch(hex: color.hex, name: color.name, isSelected: viewModel.selectedColor == color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sizePicker(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Size").font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
                Spacer()
                if product.sizes != [.oneSize] {
                    Button("Size Guide") { isSizeGuidePresented = true }
                        .font(NovaFont.caption.weight(.medium))
                        .tint(NovaColor.accent)
                        .frame(minHeight: 44)
                }
            }
            FlowLayout {
                ForEach(product.sizes) { size in
                    SizeBox(size.rawValue, isSelected: viewModel.selectedSize == size) { viewModel.selectSize(size) }
                }
            }
            if viewModel.showSizeError {
                Label("Please select a size", systemImage: "exclamationmark.circle")
                    .font(NovaFont.caption)
                    .foregroundStyle(NovaColor.error)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: viewModel.showSizeError)
    }

    private func details(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(product.summary).font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
            DisclosureGroup("Details & Care") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(product.details, id: \.self) { detail in
                        Label(detail, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                    }
                }
                .padding(.top, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(NovaFont.headline)
            .tint(NovaColor.textPrimary)
            DisclosureGroup("Shipping & Returns") {
                Text("Free standard shipping on every order. Free returns within 30 days.")
                    .font(NovaFont.body)
                    .foregroundStyle(NovaColor.textSecondary)
                    .padding(.top, Spacing.sm)
            }
            .font(NovaFont.headline)
            .tint(NovaColor.textPrimary)
        }
    }

    @ViewBuilder
    private func reviewsTeaser(_ product: Product) -> some View {
        if let review = viewModel.reviews?.reviews.first {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Reviews", actionTitle: "See All") { router.push(.reviews(product)) }
                ReviewRow(review: review)
            }
        }
    }

    private func addToCartBar(_ product: Product) -> some View {
        NovaButton(product.inStock ? "Add to Cart" : "Sold Out", systemImage: product.inStock ? "bag" : nil) {
            if viewModel.addToCart() == .needsSize {
                sizeErrorCount += 1
            } else {
                addedCount += 1
                toast = "Added to your bag"
            }
        }
        .disabled(!product.inStock)
        .accessibilityIdentifier("product.addToCart")
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.md)
        .background(.bar)
    }
}

private struct GalleryItem: Identifiable {
    let index: Int
    var id: Int {
        index
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            configuration.icon.font(.system(size: 4)).foregroundStyle(NovaColor.textSecondary)
            configuration.title.font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
        }
    }
}

/// Swipeable hero images with page dots; tap opens the zoomable gallery.
struct ImagePager: View {
    let product: Product
    let onOpen: (Int) -> Void
    @State private var page: Int? = 0

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(product.imageURLs.enumerated()), id: \.offset) { index, url in
                    Button { onOpen(index) } label: {
                        RemoteImage(url)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal)
                    .accessibilityLabel("Image \(index + 1) of \(product.imageURLs.count). Double tap to zoom.")
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .aspectRatio(4 / 5, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            WishlistButton(product: product)
                .padding(.top, 100)
                .padding(.trailing, Spacing.sm)
        }
        .overlay(alignment: .bottom) {
            if product.imageURLs.count > 1 {
                HStack(spacing: 6) {
                    ForEach(product.imageURLs.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == (page ?? 0) ? NovaColor.textPrimary : NovaColor.textPrimary.opacity(0.25))
                            .frame(width: index == (page ?? 0) ? 16 : 6, height: 6)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, Spacing.md)
                .animation(.snappy, value: page)
                .accessibilityHidden(true)
            }
        }
    }
}

struct ReviewRow: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text(review.author.prefix(1))
                    .font(NovaFont.headline)
                    .foregroundStyle(NovaColor.accent)
                    .frame(width: 36, height: 36)
                    .background(NovaColor.accentMuted, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.author).font(NovaFont.headline).foregroundStyle(NovaColor.textPrimary)
                    if review.isVerified {
                        Label("Verified Buyer", systemImage: "checkmark.seal.fill")
                            .font(NovaFont.caption)
                            .foregroundStyle(NovaColor.success)
                    }
                }
                Spacer()
                Text(review.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(NovaFont.caption)
                    .foregroundStyle(NovaColor.textSecondary)
            }
            RatingView(rating: Double(review.rating))
            Text(review.body).font(NovaFont.body).foregroundStyle(NovaColor.textPrimary)
            if !review.photoURLs.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ForEach(review.photoURLs, id: \.self) { url in
                        RemoteImage(url)
                            .frame(width: 64, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                }
            }
        }
        .novaCard()
        .accessibilityElement(children: .combine)
    }
}
