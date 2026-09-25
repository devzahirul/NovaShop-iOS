import SwiftUI

public enum NovaButtonKind: Sendable {
    case primary, secondary, outline, ghost
}

/// The one button style. Pressed state, disabled state, loading and Dynamic Type are handled here
/// so screens only ever say `.buttonStyle(.nova(.primary))`.
public struct NovaButtonStyle: ButtonStyle {
    let kind: NovaButtonKind
    let isFullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(kind: NovaButtonKind = .primary, isFullWidth: Bool = true) {
        self.kind = kind
        self.isFullWidth = isFullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NovaFont.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: 50)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(NovaColor.border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: NovaColor.onAccent
        case .secondary: NovaColor.accent
        case .outline, .ghost: NovaColor.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: NovaColor.accent
        case .secondary: NovaColor.accentMuted
        case .outline: NovaColor.surface
        case .ghost: .clear
        }
    }
}

public extension ButtonStyle where Self == NovaButtonStyle {
    static func nova(_ kind: NovaButtonKind = .primary, fullWidth: Bool = true) -> NovaButtonStyle {
        NovaButtonStyle(kind: kind, isFullWidth: fullWidth)
    }
}

/// Primary call-to-action with a built-in progress state. While loading the button is disabled
/// (prevents double submits — e.g. placing an order twice) and announces progress to VoiceOver.
public struct NovaButton: View {
    let title: String
    let systemImage: String?
    let kind: NovaButtonKind
    let isLoading: Bool
    let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        kind: NovaButtonKind = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: Spacing.sm) {
                    Text(title)
                    if let systemImage {
                        Image(systemName: systemImage).imageScale(.small)
                    }
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(kind == .primary ? NovaColor.onAccent : NovaColor.accent)
                }
            }
        }
        .buttonStyle(.nova(kind))
        .disabled(isLoading)
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

/// Circular icon button used over imagery (wishlist heart, share, close).
public struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    public init(systemImage: String, accessibilityLabel: String, tint: Color = NovaColor.textPrimary, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.footnote).weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .frame(width: 44, height: 44) // HIG minimum hit target
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
