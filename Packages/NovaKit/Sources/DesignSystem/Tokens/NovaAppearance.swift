import UIKit

/// Global UIKit appearance that SwiftUI has no API for (serif navigation titles).
/// Called once from the root view; costs microseconds and keeps every screen consistent
/// without per-screen `.toolbar { ToolbarItem(.principal) }` hacks.
public enum NovaAppearance {
    @MainActor
    public static func configure() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .regular)]
        appearance.titleTextAttributes = [.font: serif(.headline, weight: .medium)]
    }

    /// New York at a Dynamic Type text style — scales with the user's text size.
    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        let descriptor = (base.withDesign(.serif) ?? base).addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
    }
}
