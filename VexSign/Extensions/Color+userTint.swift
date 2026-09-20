//
//  Color+userTint.swift
//  VexSign — single source of truth for tint & app palette
//  Keeps light/dark contrast safe and all surfaces organized.
//

import SwiftUI
import AltSourceKit

extension Color {
    /// Canonical default — must match AppearanceTintColorView's "Default".
    static let defaultUserTintHex = "#848ef9"

    /// User-selected tint, always valid.
    static var userTint: Color {
        Color(hex: UserDefaults.standard.string(forKey: "VexSign.userTintColor") ?? defaultUserTintHex)
    }

    /// Darker sibling for gradients, pressed states and secondary fills.
    static var userTintDeep: Color {
        Color(uiColor: UIColor(userTint).darkened())
    }

    /// Organized semantic surface colors (avoid hard-coded UIColors scattered in Views).
    static var vexBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var vexCard: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var vexSeparator: Color { Color(uiColor: .separator).opacity(0.55) }

    /// For non-interactive placeholders / disabled controls — single path so nothing looks “washed out” differently.
    static var vexDisabled: Color { .secondary.opacity(0.55) }
}

private extension UIColor {
    func darkened() -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(
            hue: hue,
            saturation: min(saturation * 1.08, 1),
            // Floor keeps a near-black tint visible in dark mode; ceiling prevents blowout in light mode.
            brightness: min(max(brightness * 0.64, 0.34), 0.80),
            alpha: alpha
        )
    }
}
