import DesignSystem
import Domain
import ProductUI
import Routing
import SwiftUI

/// Wishlist (design 15). Renders straight from the shared store — no view model needed, because
/// there is no screen-specific state or async work. Adding a VM here would be ceremony.
public struct WishlistView: View {
    @Environment(WishlistStore.self) private var wishlist
    @Environment(Router.self) private var router

    public init() {}

    public var body: some View {
        Group {
            if wishlist.products.isEmpty {
                EmptyStateView(
                    systemImage: "heart",
                    title: "Your wishlist is empty",
                    message: "Tap the heart on anything you love and it will be waiting for you here.",
                    actionTitle: "Start Shopping"
                ) { router.select(.shop) }
            } else {
                ScrollView {
                    ProductGrid(products: wishlist.products)
                        .padding(Spacing.screen)
                        .animation(.snappy, value: wishlist.products)
                }
            }
        }
        .novaScreenBackground()
        .navigationTitle(wishlist.products.isEmpty ? "Wishlist" : "Wishlist (\(wishlist.count))")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { CartToolbarButton() } }
    }
}

/// Recently viewed (design 33) — same shape, different store.
public struct RecentlyViewedView: View {
    @Environment(RecentlyViewedStore.self) private var recents
    @Environment(Router.self) private var router

    public init() {}

    public var body: some View {
        Group {
            if recents.products.isEmpty {
                EmptyStateView(
                    systemImage: "clock",
                    title: "Nothing here yet",
                    message: "Products you view will appear here so you can find them again.",
                    actionTitle: "Browse"
                ) { router.select(.shop) }
            } else {
                ScrollView {
                    ProductGrid(products: recents.products).padding(Spacing.screen)
                }
            }
        }
        .novaScreenBackground()
        .navigationTitle("Recently Viewed")
        .toolbar {
            if !recents.products.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { recents.clear() }.tint(NovaColor.accent)
                }
            }
        }
    }
}
