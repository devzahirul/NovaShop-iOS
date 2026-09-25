import DesignSystem
import Domain
import NovaCore
import Routing
import SwiftUI

/// Account (design 31). Guests see a sign-in prompt instead of a wall — browsing never requires auth.
public struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(WishlistStore.self) private var wishlist
    @State private var isConfirmingSignOut = false

    public init() {}

    public var body: some View {
        List {
            Section { header }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section {
                row("My Orders", icon: "shippingbox", route: .orders)
                row("Wishlist", icon: "heart", value: wishlist.products.isEmpty ? nil : "\(wishlist.count)") { router.select(.wishlist) }
                row("Recently Viewed", icon: "clock", route: .recentlyViewed)
                row("Addresses", icon: "mappin.and.ellipse", route: .addresses)
                row("Payment Methods", icon: "creditcard", route: .paymentMethods)
            }
            Section {
                row("Notifications", icon: "bell", route: .notifications)
                row("Settings", icon: "gearshape", route: .settings)
                if let helpURL = URL(string: "https://novashop.example/help") {
                    Link(destination: helpURL) {
                        Label("Help Center", systemImage: "questionmark.circle")
                            .foregroundStyle(NovaColor.textPrimary)
                    }
                }
            }
            if session.isSignedIn {
                Section {
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                        .accessibilityIdentifier("account.signOut")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .novaScreenBackground()
        .navigationTitle("Account")
        .confirmationDialog("Sign out of NovaShop?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
        }
    }

    @ViewBuilder
    private var header: some View {
        if let user = session.user {
            HStack(spacing: Spacing.lg) {
                Text(user.initials)
                    .font(NovaFont.title2)
                    .foregroundStyle(NovaColor.accent)
                    .frame(width: 64, height: 64)
                    .background(NovaColor.accentMuted, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name).font(NovaFont.title3).foregroundStyle(NovaColor.textPrimary)
                    Text(user.email).font(NovaFont.callout).foregroundStyle(NovaColor.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.lg)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("account.header")
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Welcome to NovaShop").font(NovaFont.title2)
                Text("Sign in to track orders, save addresses and check out faster.")
                    .font(NovaFont.body)
                    .foregroundStyle(NovaColor.textSecondary)
                Button("Sign In or Create Account") { router.present(.auth(then: nil)) }
                    .buttonStyle(.nova(.primary))
                    .accessibilityIdentifier("account.signIn")
            }
            .padding(.vertical, Spacing.lg)
        }
    }

    private func row(_ title: String, icon: String, value: String? = nil, route: Route) -> some View {
        row(title, icon: icon, value: value) { router.push(route) }
    }

    private func row(_ title: String, icon: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(NovaColor.textPrimary)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(NovaColor.textSecondary)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(NovaColor.textTertiary)
            }
            .font(NovaFont.body)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings (design 32)

public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String {
        rawValue
    }

    public var title: String {
        rawValue.capitalized
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public struct SettingsView: View {
    @AppStorage("settings.pushNotifications") private var pushNotifications = true
    @AppStorage("settings.emailNotifications") private var emailNotifications = true
    @AppStorage("settings.marketing") private var marketing = false
    @AppStorage("settings.appearance") private var appearance: AppearancePreference = .system
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingDelete = false
    @State private var deleteError: UserFacingError?

    public init() {}

    public var body: some View {
        Form {
            Section("Notifications") {
                ToggleRow("Push Notifications", isOn: $pushNotifications)
                ToggleRow("Email Notifications", isOn: $emailNotifications)
                ToggleRow("Marketing Communications", isOn: $marketing)
            }
            Section("Preferences") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    LabeledContent(
                        "Language",
                        value: Locale.current
                            .localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
                    )
                }
                .foregroundStyle(NovaColor.textPrimary)
                LabeledContent("Currency", value: "USD ($)")
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.appearance")
            }
            Section("Privacy") {
                if let url = URL(string: "https://novashop.example/privacy") {
                    Link("Privacy Policy", destination: url).foregroundStyle(NovaColor.textPrimary)
                }
                if session.isSignedIn {
                    Button("Delete Account", role: .destructive) { isConfirmingDelete = true }
                }
            }
            Section("About") {
                LabeledContent("App Version", value: Bundle.main.appVersion)
                #if DEBUG
                    DeveloperSection()
                #endif
            }
        }
        .tint(NovaColor.accent)
        .scrollContentBackground(.hidden)
        .novaScreenBackground()
        .navigationTitle("Settings")
        // App Store guideline 5.1.1(v): account deletion must be available in-app.
        .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task {
                    do {
                        try await session.deleteAccount()
                        router.popToRoot()
                    } catch {
                        deleteError = error.userFacing
                    }
                }
            }
        } message: {
            Text("This permanently removes your profile, addresses and order history. This can't be undone.")
        }
        .alert(deleteError?.title ?? "", isPresented: Binding(get: { deleteError != nil }, set: { _ in deleteError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError?.message ?? "")
        }
    }
}

#if DEBUG
    /// Debug-only diagnostics: launch timings measured in-process (compiled out of Release).
    private struct DeveloperSection: View {
        var body: some View {
            let timeline = LaunchTimeline.shared
            LabeledContent("First frame", value: timeline.firstFrame?.formattedMilliseconds ?? "—")
            LabeledContent("Home content", value: timeline.contentReady?.formattedMilliseconds ?? "—")
        }
    }
#endif

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
