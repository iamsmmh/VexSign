//
//  TabBarSettingsView.swift
//  VexSign — fixed six-tab navigation shell
//

import SwiftUI
import NimbleViews

struct TabBarSettingsView: View {
    @ObservedObject private var preferences = TabBarPreferences.shared

    var body: some View {
        NBList(.localized("Tab Bar"), type: .list) {
            NBSection(.localized("Preview")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(TabEnum.defaultTabs, id: \.self) { tab in
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Theme.tint)
                                Text(tab.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(width: 64)
                            .padding(.vertical, 8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.separator, lineWidth: 1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(tab.title))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            } footer: {
                Text(.localized("The primary navigation order is fixed so Files, Library, Home, App Store, Downloads and Settings are always available."))
            }

            NBSection(.localized("Default Launch Tab")) {
                Picker(selection: $preferences.defaultLaunch) {
                    ForEach(TabEnum.defaultTabs, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                } label: {
                    Label(.localized("Open On Launch"), systemImage: "house.fill")
                }
                .pickerStyle(.menu)
                .tint(Theme.tint)
            } footer: {
                Text(.localized("Choose which primary tab opens when VexSign starts. Every tab remains visible in the shell."))
            }

            NBSection(.localized("Primary Tabs")) {
                ForEach(Array(TabEnum.defaultTabs.enumerated()), id: \.element) { index, tab in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.tint)
                            .frame(width: 22, height: 22)
                            .background(Theme.tintSoft, in: Circle())
                        Label(tab.title, systemImage: tab.icon)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(.localized("Always visible")))
                    }
                }
            } footer: {
                Text(.localized("These six tabs are part of VexSign's stable navigation contract and cannot be hidden or reordered."))
            }
        }
    }
}
