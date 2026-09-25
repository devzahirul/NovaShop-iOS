import SwiftUI
import UIKit

/// Semantic colour tokens. Every token resolves dynamically for light / dark and increased contrast,
/// so no view ever branches on `colorScheme` for colours.
public enum NovaColor {
    public static let background = Color(light: 0xFBF8F4, dark: 0x14110F)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1F1A17)
    public static let surfaceMuted = Color(light: 0xF3EDE6, dark: 0x2A231F)
    public static let accent = Color(light: 0xA2644A, dark: 0xD0957A)
    public static let accentMuted = Color(light: 0xEFE1D8, dark: 0x3B2A22)
    public static let onAccent = Color(light: 0xFFFFFF, dark: 0x1A120E)
    public static let textPrimary = Color(light: 0x2A211C, dark: 0xF3ECE6)
    public static let textSecondary = Color(light: 0x857970, dark: 0xA99D94)
    public static let textTertiary = Color(light: 0xB2A79F, dark: 0x7B7069)
    public static let border = Color(light: 0xE7DFD7, dark: 0x3A322C)
    public static let success = Color(light: 0x3F7D4E, dark: 0x7CC18C)
    public static let successMuted = Color(light: 0xE6F1E8, dark: 0x1F3325)
    public static let error = Color(light: 0xB3413A, dark: 0xF08A82)
    public static let star = Color(light: 0xD9962B, dark: 0xF0B650)
    public static let scrim = Color.black.opacity(0.35)
}

public extension Color {
    /// Dynamic colour from two sRGB hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Parses `#RRGGBB` (used for product swatches that come from the API).
    init(hex string: String) {
        let cleaned = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(uiColor: UIColor(hex: UInt32(cleaned, radix: 16) ?? 0x999999))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let screen: CGFloat = 20
}

public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// Typography. Everything is built on text styles so it scales with Dynamic Type; the editorial
/// voice of the design comes from Apple's New York (`design: .serif`) — a system font, so there is
/// zero font-registration cost at launch and no licensing to manage.
public enum NovaFont {
    public static let display = Font.system(.largeTitle, design: .serif)
    public static let title = Font.system(.title, design: .serif)
    public static let title2 = Font.system(.title2, design: .serif)
    public static let title3 = Font.system(.title3, design: .serif)
    public static let wordmark = Font.system(.title2, design: .serif).weight(.medium)
    public static let headline = Font.system(.subheadline).weight(.semibold)
    public static let body = Font.system(.subheadline)
    public static let callout = Font.system(.footnote)
    public static let caption = Font.system(.caption)
    public static let eyebrow = Font.system(.caption2).weight(.semibold)
    public static let price = Font.system(.subheadline).weight(.semibold).monospacedDigit()
    public static let button = Font.system(.subheadline).weight(.semibold)
}

public enum Money {
    public static let currencyCode = "USD"

    /// Locale-aware currency formatting ($129.00 / 129,00 US$ …).
    public static func format(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode))
    }
}

public extension View {
    /// Standard screen background.
    func novaScreenBackground() -> some View {
        background(NovaColor.background.ignoresSafeArea())
    }

    /// Rounded surface card with a hairline border.
    func novaCard(padding: CGFloat = Spacing.lg, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(padding)
            .background(NovaColor.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(NovaColor.border, lineWidth: 0.5)
            }
    }
}
