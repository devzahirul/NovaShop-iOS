import NovaCore
import SwiftUI

// MARK: - Skeleton

/// Shimmering placeholder. Skeletons that match the final layout make perceived load time shorter
/// than a spinner and avoid layout shift when content arrives. Honors Reduce Motion.
public struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .mask(content)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityLabel("Loading")
    }
}

public extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

public struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let radius: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = Radius.sm) {
        self.width = width
        self.height = height
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(NovaColor.surfaceMuted)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - Empty / error

public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(NovaColor.accent)
                .frame(width: 88, height: 88)
                .background(NovaColor.accentMuted, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text(title).font(NovaFont.title2).foregroundStyle(NovaColor.textPrimary)
                Text(message).font(NovaFont.body).foregroundStyle(NovaColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.nova(.primary, fullWidth: false))
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct ErrorStateView: View {
    let error: UserFacingError
    let retry: (() -> Void)?

    public init(_ error: UserFacingError, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        EmptyStateView(
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            title: error.title,
            message: error.message,
            actionTitle: error.isRetryable && retry != nil ? "Try Again" : nil,
            action: retry
        )
    }
}

// MARK: - Banner

public struct InlineBanner: View {
    public enum Style { case success, error, info }

    let text: String
    let style: Style

    public init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Label {
            Text(text).font(NovaFont.callout)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(foreground)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch style {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var foreground: Color {
        switch style {
        case .success: NovaColor.success
        case .error: NovaColor.error
        case .info: NovaColor.accent
        }
    }

    private var background: Color {
        switch style {
        case .success: NovaColor.successMuted
        case .error: NovaColor.error.opacity(0.1)
        case .info: NovaColor.accentMuted
        }
    }
}

/// Transient toast shown at the bottom ("Added to bag").
public struct ToastModifier: ViewModifier {
    @Binding var message: String?

    public func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(NovaFont.callout.weight(.medium))
                    .foregroundStyle(NovaColor.onAccent)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(NovaColor.textPrimary, in: Capsule())
                    .padding(.bottom, Spacing.xxl * 2.5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { self.message = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: message)
    }
}

public extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
