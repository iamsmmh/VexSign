//
//  TabbarView.swift
//  VexSign
//
//  A stable six-item tab shell. SwiftUI's classic TabView promotes the sixth
//  item into a "More" tab on iPhone, which is not the requested Files,
//  Library, Home, App Store, Downloads, Settings layout. This small shell keeps
//  all six destinations visible while retaining each destination's navigation
//  stack and state.
//

import SwiftUI

struct TabbarView: View {
    @ObservedObject private var tabSelection = TabSelectionObserver.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @ObservedObject private var tweakManager = TweakManager.shared
    @ObservedObject private var tabPrefs = TabBarPreferences.shared
    @AppStorage("VexSign.showSourcesUpdateBadge") private var showSourcesUpdateBadge = true
    @Namespace private var tabSelectionAnimation

    private var visibleTabs: [TabEnum] {
        tabPrefs.visibleTabs
    }

    private var currentTab: TabEnum {
        visibleTabs.contains(tabSelection.selectedTab)
            ? tabSelection.selectedTab
            : tabPrefs.resolvedLaunchTab
    }

    private var selectionBinding: Binding<TabEnum> {
        Binding(
            get: { currentTab },
            set: { select($0) }
        )
    }

    var body: some View {
        TabView(selection: selectionBinding) {
            ForEach(visibleTabs, id: \.self) { tab in
                TabEnum.view(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        // The system bar is hidden only visually; TabView still owns the
        // navigation stacks for each destination. Our six-item bar below is
        // the stable, always-visible presentation.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .onAppear {
            if !visibleTabs.contains(tabSelection.selectedTab) {
                tabSelection.selectedTab = tabPrefs.resolvedLaunchTab
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: currentTab == tab ? tab.icon : tab.iconOutline)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(height: 21)

                            if let badge = badge(for: tab), badge > 0 {
                                Text(badge > 99 ? "99+" : "\(badge)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 16, minHeight: 15)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 11, y: -7)
                            }
                        }
                        Text(tab.title)
                            .font(.caption2.weight(currentTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(currentTab == tab ? Color.userTint : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                    .background {
                        if currentTab == tab {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.tintSoft)
                                .matchedGeometryEffect(id: "selected-tab", in: tabSelectionAnimation)
                        }
                    }
                }
                .buttonStyle(VexSignFlareButtonStyle())
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(currentTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .animation(.snappy(duration: 0.28), value: currentTab)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.5)
        }
    }

    private func select(_ tab: TabEnum) {
        if tab == tabSelection.selectedTab, tab == .appStore || tab == .sources {
            tabSelection.sourcesRetapped.toggle()
        }
        tabSelection.selectedTab = tab
    }

    private func badge(for tab: TabEnum) -> Int? {
        if (tab == .appStore || tab == .sources) && showSourcesUpdateBadge {
            return updateChecker.updateCount
        }
        if tab == .tweaks {
            return tweakManager.defaultInjectCount
        }
        if tab == .downloads {
            return DownloadManager.shared.downloads.filter { $0.isActive }.count
        }
        return nil
    }
}
