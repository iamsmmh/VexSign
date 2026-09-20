//
//  Theme.swift
//  VexSign — central design tokens (single source of truth)
//  All surfaces, spacing, radius and semantic colors live here.
//

import SwiftUI
import NimbleViews

enum Theme {
    // MARK: - Surfaces
    static var background: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var cardElevated: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var separator: Color { Color(uiColor: .separator).opacity(0.55) }
    static var quaternary: Color { Color(uiColor: .quaternarySystemFill) }

    // MARK: - Text
    static var primary: Color { .primary }
    static var secondary: Color { .secondary }
    static var tertiary: Color { Color(uiColor: .tertiaryLabel) }

    // MARK: - Tint
    static var tint: Color { Color.userTint }
    static var tintDeep: Color { Color.userTintDeep }
    static var tintSoft: Color { Color.userTint.opacity(0.12) }

    // MARK: - Metrics
    enum Radius {
        static let large: CGFloat = NBRadius.large // 28 on iOS26, 12 otherwise
        static let card: CGFloat = 18
        static let medium: CGFloat = 12
        static let pill: CGFloat = 999
    }
    enum Spacing {
        static let cardPadding: CGFloat = 14
        static let section: CGFloat = 20
        static let row: CGFloat = NBSpacing.row
    }

    // MARK: - Shadows
    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.20) : Color.black.opacity(0.06)
    }

    // MARK: - Gradients
    static var appStoreGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.05, green: 0.38, blue: 0.96), Color(red: 0.32, green: 0.60, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var filesGradient: LinearGradient {
        LinearGradient(colors: [Color.userTint.opacity(0.22), Color.userTintDeep.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
