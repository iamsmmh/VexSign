//
//  AppStyle.swift
//  VexSign
//
//  Small, dependency-free presentation preferences shared by the app shell and
//  settings. Keeping these here lets a font/theme choice apply consistently
//  without coupling feature views to UIKit.
//

import SwiftUI

enum VexSignVisualTheme: String, CaseIterable, Identifiable {
    case system
    case luna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .luna: return "Luna"
        }
    }

    var description: String {
        switch self {
        case .system: return "Use the standard grouped iOS surfaces."
        case .luna: return "A soft indigo, glassy VexSign theme inspired by moonlight."
        }
    }
}

enum VexSignFontFamily: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum VexSignStylePreferences {
    static let visualThemeKey = "VexSign.visualTheme"
    static let fontFamilyKey = "VexSign.fontFamily"
    static let fontScaleKey = "VexSign.fontScale"
    static let flareAnimationsKey = "VexSign.flareAnimations"

    static func font(familyRawValue: String, scale: Double) -> Font {
        let family = VexSignFontFamily(rawValue: familyRawValue) ?? .system
        let safeScale = min(max(scale, 0.85), 1.25)
        return .system(size: 17 * safeScale, design: family.design)
    }
}

/// A restrained FlareStore-inspired press treatment: a tiny scale/opacity
/// change and no layout-affecting geometry. It remains instantaneous when the
/// user enables Reduce Motion or turns Flare animations off.
struct VexSignFlareButtonStyle: ButtonStyle {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && enabled ? 0.86 : 1)
            .animation(
                enabled && !reduceMotion
                    ? .spring(response: 0.24, dampingFraction: 0.72)
                    : .linear(duration: 0),
                value: configuration.isPressed
            )
    }
}
