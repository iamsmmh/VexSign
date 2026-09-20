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
            // Live preview — Files·Library·Home·App Store·Downloads·Settings
            NBSection(.localized("Preview")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(_prefs.visibleTabs, id: \.self) { tab in
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.tint)
                                Text(tab.title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(width: 56)
                            .padding(.vertical, 8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(tab.title))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            } footer: {
                Text(verbatim: String.localized("Your current order: %@.", arguments: _prefs.visibleTabs.map { $0.title }.joined(separator: " • ")))
            }

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
