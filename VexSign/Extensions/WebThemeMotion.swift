//
//  WebThemeMotion.swift
//  VexSign
//
//  Small native motion treatment for the optional Flare presentation.
//  It uses no website JavaScript or assets and respects Reduce Motion plus the
//  existing Flare Touch Animations preference.
//

import SwiftUI

struct VexSignWebMotionModifier: ViewModifier {
    @AppStorage(VexSignStylePreferences.visualThemeKey) private var visualTheme = VexSignVisualTheme.system.rawValue
    @AppStorage(VexSignStylePreferences.flareAnimationsKey) private var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightPhase = false

    private var isEnabled: Bool {
        visualTheme == VexSignVisualTheme.flare.rawValue && animationsEnabled && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isEnabled {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Theme.websiteAccent.opacity(0.72), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 220, height: 2)
                        .blur(radius: 0.4)
                        .offset(x: highlightPhase ? proxy.size.width : -240)
                        .animation(
                            .easeInOut(duration: 2.8).repeatForever(autoreverses: false),
                            value: highlightPhase
                        )
                    }
                    .frame(height: 2)
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear { highlightPhase = true }
                }
            }
    }
}

extension View {
    func vexSignWebMotion() -> some View {
        modifier(VexSignWebMotionModifier())
    }
}
