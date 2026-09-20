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
    /// The original VexSign/Ksign-style iOS surfaces.
    case system
    /// The existing VexSign indigo presentation.
    case luna
    /// Optional website-inspired Flare presentation for the native app.
    // Keep the persisted raw value for users who selected the previous label.
    case flare = "flareWeb"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Base / Ksign"
        case .luna: return "Luna"
        case .flare: return "Flare"
        }
    }

    var description: String {
        switch self {
        case .system: return "Keep the original grouped iOS and Ksign-style surfaces."
        case .luna: return "A soft indigo, glassy VexSign theme inspired by moonlight."
        case .flare: return "A dark, glassy native presentation inspired by the FlareStore website."
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
///
/// Style values are captured at init from the `AppearanceStore` snapshot
/// instead of via `@AppStorage`: property wrappers like `@AppStorage` are only
/// guaranteed to update inside views, and a `ButtonStyle` is not a view. The
/// environment (Reduce Motion) is read inside the body view below for the
/// same reason.
struct VexSignFlareButtonStyle: ButtonStyle {
    var enabled = true
    var isFlareTheme = AppearanceStore.snapshot().isFlare

    init(enabled: Bool = true) {
        self.enabled = enabled
        self.isFlareTheme = AppearanceStore.snapshot().isFlare
    }

    func makeBody(configuration: Configuration) -> some View {
        _FlarePressBody(
            configuration: configuration,
            enabled: enabled,
            isFlareTheme: isFlareTheme
        )
    }
}

private struct _FlarePressBody: View {
    let configuration: VexSignFlareButtonStyle.Configuration
    let enabled: Bool
    let isFlareTheme: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressedScale: CGFloat = isFlareTheme ? 0.965 : 0.97
        let response: Double = isFlareTheme ? 0.30 : 0.24
        let damping: Double = isFlareTheme ? 0.68 : 0.72

        configuration.label
            .scaleEffect(configuration.isPressed && enabled && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed && enabled ? (isFlareTheme ? 0.82 : 0.86) : 1)
            .animation(
                enabled && !reduceMotion
                    ? .spring(response: response, dampingFraction: damping)
                    : .linear(duration: 0),
                value: configuration.isPressed
            )
    }
}
