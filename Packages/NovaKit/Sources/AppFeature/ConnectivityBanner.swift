import DesignSystem
import Domain
import NovaCore
import SwiftUI

/// App-wide "you're offline" pill. Reassures instead of alarming: shopping keeps working and
/// changes are saved; they sync automatically when the connection returns.
struct ConnectivityBanner: View {
    let network: NetworkMonitor
    let cart: CartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !network.isOnline {
                Label {
                    Text(cart.pendingItemIDs.isEmpty ? "You're offline" : "Offline · changes will sync")
                } icon: {
                    Image(systemName: "wifi.slash")
                }
                .font(NovaFont.caption.weight(.semibold))
                .foregroundStyle(NovaColor.onAccent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(NovaColor.textPrimary.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.top, Spacing.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("connectivity.offline")
            }
        }
        .animation(.snappy, value: network.isOnline)
        .allowsHitTesting(false)
    }
}
