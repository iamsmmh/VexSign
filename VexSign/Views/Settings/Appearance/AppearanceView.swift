//
//  AppearanceView.swift
//  VexSign — organized, tint-coherent appearance settings
//
import SwiftUI
import NimbleViews
import UIKit

struct AppearanceView: View {
    @AppStorage("VexSign.userInterfaceStyle") private var _userIntefacerStyle: Int = UIUserInterfaceStyle.unspecified.rawValue

    @AppStorage("VexSign.storeCellAppearance") private var _storeCellAppearance: Int = 0
    private let _storeCellAppearanceMethods: [(name: String, desc: String)] = [
        (.localized("Standard"), .localized("Default style for the app, only includes subtitle.")),
        (.localized("Big Description"), .localized("Adds the localized description of the app."))
    ]

    @AppStorage("com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck") private var _ignoreSolariumLinkedOnCheck: Bool = false
    @AppStorage("VexSign.sourcesTabShowAllReposDirectly") private var _sourcesTabShowAllReposDirectly: Bool = false
    @AppStorage("VexSign.sourcesShowUpdatesAsTab") private var _sourcesShowUpdatesAsTab: Bool = false
    @AppStorage("VexSign.showSourcesUpdateBadge") private var _showSourcesUpdateBadge: Bool = true
    @AppStorage("VexSign.shouldTintIcons") private var _shouldTintIcons: Bool = false
    @AppStorage("VexSign.shouldChangeIconsBasedOffStyle") private var _shouldChangeIconsBasedOffStyle: Bool = false
    @AppStorage("VexSign.userTintColor") private var _selectedColorHex: String = "#848ef9"
    @AppStorage(VexSignStylePreferences.visualThemeKey) private var _visualTheme = VexSignVisualTheme.system.rawValue
    @AppStorage(VexSignStylePreferences.fontFamilyKey) private var _fontFamily = VexSignFontFamily.system.rawValue
    @AppStorage(VexSignStylePreferences.fontScaleKey) private var _fontScale = 1.0
    @AppStorage(VexSignStylePreferences.flareAnimationsKey) private var _flareAnimations = true

    private var _tintColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: _selectedColorHex) },
            set: { _selectedColorHex = $0.toHex() }
        )
    }

    var body: some View {
        NBList(.localized("Appearance")) {
            Section {
                Picker(.localized("Appearance"), selection: $_userIntefacerStyle) {
                    ForEach(UIUserInterfaceStyle.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label(.localized("Interface Style"), systemImage: "moonphase")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.userTint)
            }

            // Organized theme section — tint picker grouped, not a loose horizontal strip
            NBSection(.localized("Theme")) {
                AppearanceTintColorView()
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            } footer: {
                Text(.localized("The tint colors navigation, buttons and highlights across the app."))
            }

            NBSection(.localized("Visual Theme"), systemName: "sparkles") {
                Picker(.localized("Theme"), selection: $_visualTheme) {
                    ForEach(VexSignVisualTheme.allCases) { theme in
                        NBTitleWithSubtitleView(title: theme.title, subtitle: theme.description)
                            .tag(theme.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            } footer: {
                Text(.localized("Luna is an original VexSign dark, glassy presentation. It changes surfaces and motion context without changing signing behavior."))
            }

            Section {
                ColorPicker(.localized("Custom Theme Color"), selection: _tintColorBinding, supportsOpacity: false)
                    .tint(Color.userTint)
            } footer: {
                Text(.localized("Pick any color if the presets don’t fit. It updates instantly."))
            }

            NBSection(.localized("Font & Motion"), systemName: "textformat") {
                Picker(.localized("Font"), selection: $_fontFamily) {
                    ForEach(VexSignFontFamily.allCases) { family in
                        Text(family.title)
                            .font(.system(.body, design: family.design))
                            .tag(family.rawValue)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("A")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $_fontScale, in: 0.9...1.15, step: 0.05)
                        .tint(Color.userTint)
                    Text("A")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.userTint)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(.localized("Font size")))

                Toggle(.localized("Flare Touch Animations"), isOn: $_flareAnimations)
                    .tint(Color.userTint)
            } footer: {
                Text(.localized("Choose the app font and size. Flare touch feedback adds a subtle spring to buttons without changing layout."))
            }

            if #available(iOS 18.0, *) {
                NBSection(.localized("Library Icons")) {
                    Toggle(.localized("Dynamic Icons"), isOn: $_shouldChangeIconsBasedOffStyle)
                        .tint(Color.userTint)
                    if #available(iOS 18.2, *) {
                        Toggle(.localized("Tinted Icons"), isOn: $_shouldTintIcons)
                            .tint(Color.userTint)
                    }
                } footer: {
                    Text(.localized("Tinted icons use your theme color. Dynamic icons adapt to light & dark."))
                }
            }

            NBSection(.localized("Sources")) {
                Picker(.localized("Store Cell Appearance"), selection: $_storeCellAppearance) {
                    ForEach(0..<_storeCellAppearanceMethods.count, id: \.self) { index in
                        let method = _storeCellAppearanceMethods[index]
                        NBTitleWithSubtitleView(title: method.name, subtitle: method.desc).tag(index)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
                Toggle(.localized("Show All Repos by Default"), isOn: $_sourcesTabShowAllReposDirectly).tint(Color.userTint)
                Toggle(.localized("Show Updates as Tab"), isOn: $_sourcesShowUpdatesAsTab).tint(Color.userTint)
                Toggle(.localized("Update Count Badge"), isOn: $_showSourcesUpdateBadge).tint(Color.userTint)
                NavigationLink(destination: IgnoredUpdatesView()) {
                    Label(.localized("Ignored Updates"), systemImage: "bell.slash")
                }
            } footer: {
                Text(.localized("When enabled, the Sources tab shows all apps directly. Toggle off to manage sources. The update count badge shows the number of available app updates on the Sources tab."))
            }

            if #available(iOS 19.0, *) {
                NBSection(.localized("Experiments")) {
                    Toggle(.localized("Enable Liquid Glass"), isOn: $_ignoreSolariumLinkedOnCheck).tint(Color.userTint)
                } footer: {
                    Text(.localized("This enables liquid glass for this app, this requires a restart of the app to take effect."))
                }
            }
        }
        .onChange(of: _userIntefacerStyle) { value in
            if let style = UIUserInterfaceStyle(rawValue: value) {
                UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
            }
        }
        .onChange(of: _ignoreSolariumLinkedOnCheck) { _ in
            UIApplication.shared.suspendAndReopen()
        }
        .onChange(of: _selectedColorHex) { hex in
            UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: hex))
        }
    }
}
