//
//  TabBarSettingsView.swift
//  VexSign
//
//  Reorder, hide, and pick the default launch tab. Backed by TabBarPreferences,
//  which both tab bars read from.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct TabBarSettingsView: View {
	@ObservedObject private var _prefs = TabBarPreferences.shared

	var body: some View {
		NBList(.localized("Tab Bar"), type: .list) {
			NBSection(.localized("Interface")) {
				Toggle(isOn: Binding(
					get: { _prefs.isMinimal },
					set: { _prefs.setMinimal($0) }
				)) {
					Label(.localized("Minimal Mode"), systemImage: "square.split.1x2")
				}
			} footer: {
				Text(.localized("Hides every tab except Home and Settings. Turn it off here, or from Home, to get the rest back."))
			}

			NBSection(.localized("Default Launch Tab")) {
				Picker(selection: $_prefs.defaultLaunch) {
					ForEach(_prefs.visibleTabs, id: \.self) { tab in
						Label(tab.title, systemImage: tab.icon).tag(tab)
					}
				} label: {
					Label(.localized("Open On Launch"), systemImage: "house")
				}
				.pickerStyle(.menu)
			} footer: {
				Text(.localized("Which tab the app opens to."))
			}

			NBSection(.localized("Interface")) {
				Toggle(isOn: Binding(
					get: { _prefs.isMinimal },
					set: { _prefs.setMinimal($0) }
				)) {
					Label(.localized("Minimal Mode"), systemImage: "square.grid.2x2")
				}
			} footer: {
				Text(.localized("Hides every tab except Home and Settings, for a calmer layout. Turn it off here at any time — nothing is deleted."))
			}

			NBSection(.localized("Tabs")) {
				ForEach(_prefs.orderedTabs, id: \.self) { tab in
					_row(for: tab)
				}
				.onMove { source, destination in
					_prefs.move(from: source, to: destination)
				}
			} footer: {
				Text(.localized("Drag to reorder (tap Edit). Hidden tabs stay reachable from Home. Home and Settings can't be hidden."))
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) { EditButton() }
		}
	}

	@ViewBuilder
	private func _row(for tab: TabEnum) -> some View {
		if _prefs.isMinimal {
			// Nothing to hide while Minimal Mode is on; the toggle above governs.
			HStack {
				Label(tab.title, systemImage: tab.icon)
				Spacer()
				if TabBarPreferences.minimalTabs.contains(tab) {
					Image(systemName: "checkmark")
						.font(.caption)
						.foregroundStyle(.secondary)
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
		} else {
			HStack {
				Label(tab.title, systemImage: tab.icon)
				Spacer()
				Image(systemName: "lock")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
}
