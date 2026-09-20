//
//  TabBarSettingsView.swift
//  VexSign — organized, no duplicate Minimal Mode
//

import SwiftUI
import NimbleViews

struct TabBarSettingsView: View {
    @ObservedObject private var _prefs = TabBarPreferences.shared

    var body: some View {
        NBList(.localized("Tab Bar"), type: .list) {
            NBSection(.localized("Layout")) {
                Toggle(isOn: Binding(
                    get: { _prefs.isMinimal },
                    set: { _prefs.setMinimal($0) }
                )) {
                    Label(.localized("Minimal Mode"), systemImage: "square.split.1x2")
                }
                .tint(Color.userTint)
            } footer: {
                Text(.localized("Hides every tab except Home and Settings for a calmer layout. Turn it off here at any time — Home has a shortcut too. Nothing is deleted."))
            }

            NBSection(.localized("Default Launch Tab")) {
                Picker(selection: $_prefs.defaultLaunch) {
                    ForEach(_prefs.visibleTabs, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                } label: {
                    Label(.localized("Open On Launch"), systemImage: "house.fill")
                }
                .pickerStyle(.menu)
                .tint(Color.userTint)
            } footer: {
                Text(.localized("Which tab the app opens to. Settings and Home are always available."))
            }

            NBSection(.localized("Tabs")) {
                ForEach(_prefs.orderedTabs, id: \.self) { tab in
                    _row(for: tab)
                }
                .onMove { source, destination in
                    _prefs.move(from: source, to: destination)
                }
            } footer: {
                Text(.localized("Drag to reorder (tap Edit). Hidden tabs stay reachable from Home. Home and Settings can’t be hidden — they’re your way back."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().tint(Color.userTint) }
        }
    }

    @ViewBuilder
    private func _row(for tab: TabEnum) -> some View {
        if _prefs.isMinimal {
            HStack {
                Label(tab.title, systemImage: tab.icon)
                Spacer()
                if TabBarPreferences.minimalTabs.contains(tab) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.userTint)
                } else {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(TabBarPreferences.minimalTabs.contains(tab) ? .primary : .secondary)
        } else if _prefs.isHideable(tab) {
            Toggle(isOn: Binding(
                get: { !_prefs.isHidden(tab) },
                set: { _prefs.setHidden(tab, !$0) }
            )) {
                Label(tab.title, systemImage: tab.icon)
            }
            .tint(Color.userTint)
        } else {
            HStack {
                Label(tab.title, systemImage: tab.icon)
                Spacer()
                Label(.localized("Always visible"), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
