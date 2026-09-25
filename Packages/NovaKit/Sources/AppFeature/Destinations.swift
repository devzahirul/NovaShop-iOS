import AccountFeature
import CartFeature
import CatalogFeature
import CheckoutFeature
import Domain
import HomeFeature
import ProductFeature
import Routing
import SwiftUI
import WishlistFeature

/// Feature factories. Every view model is built here with its concrete dependencies, so features
/// stay ignorant of each other and of `Data`. Adding a screen = one `Route` case + one line here.
@MainActor
extension AppContainer {
    func makeHome() -> some View {
        HomeView(viewModel: HomeViewModel(catalog: self.catalog))
    }

    func makeShop() -> some View {
        ShopView(viewModel: ShopViewModel(catalog: self.catalog))
    }

    func makeSearch() -> some View {
        SearchView(viewModel: SearchViewModel(catalog: self.catalog, history: self.searchHistory))
    }

    func makeWishlist() -> some View {
        WishlistView()
    }

    func makeAccount() -> some View {
        AccountView()
    }

    private func listing(_ query: ProductQuery) -> ProductListingViewModel {
        ProductListingViewModel(query: query, catalog: self.catalog)
    }

    private func addCardViewModel() -> AddCardViewModel {
        AddCardViewModel(profile: self.profile)
    }

    @ViewBuilder
    func destination(for route: Route) -> some View {
        switch route {
        case let .product(id, preview):
            ProductDetailView(viewModel: ProductDetailViewModel(
                productID: id, preview: preview, catalog: self.catalog, cart: self.cart, recentlyViewed: self.recentlyViewed
            ))
        case let .category(category):
            CategoryView(category: category, viewModel: self.listing(ProductQuery(categoryIDs: [category.id])))
        case let .collection(collection):
            CollectionView(collection: collection, viewModel: self.listing(ProductQuery(tag: collection.productTag)))
        case let .productList(title, query):
            ProductListingView(title: title, viewModel: self.listing(query))
        case let .searchResults(query):
            ProductListingView(title: "“\(query.text)”", viewModel: self.listing(query))
        case let .reviews(product):
            ReviewsView(viewModel: ReviewsViewModel(product: product, catalog: self.catalog))
        case .cart:
            CartView()
        case .coupon:
            CouponView(viewModel: CouponViewModel(cart: self.cart))
        case .checkout:
            CheckoutView(
                viewModel: CheckoutViewModel(
                    cart: self.cart, profile: self.profile, orders: self.orders,
                    isOnline: { [network = self.network] in network.isOnline }
                ),
                addCardViewModel: self.addCardViewModel
            )
        case let .orderConfirmation(order):
            OrderConfirmationView(order: order)
        case .orders:
            OrdersView(viewModel: OrdersViewModel(service: self.orders))
        case let .order(order):
            OrderDetailView(order: order)
        case let .returnRequest(order):
            ReturnRequestView(order: order)
        case .recentlyViewed:
            RecentlyViewedView()
        case .addresses:
            AddressListView(viewModel: AddressListViewModel(profile: self.profile))
        case .addAddress:
            AddAddressView(viewModel: AddAddressViewModel(profile: self.profile, prefillName: self.session.user?.name ?? ""))
        case .paymentMethods:
            PaymentMethodsView(viewModel: PaymentMethodsViewModel(profile: self.profile), addCardViewModel: self.addCardViewModel)
        case .notifications:
            NotificationsView(viewModel: NotificationsViewModel(repository: self.notifications))
        case .settings:
            SettingsView(backend: self.backendDescription)
        }
    }
}
