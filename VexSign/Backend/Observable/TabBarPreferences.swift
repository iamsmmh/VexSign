//
//  TabBarPreferences.swift
//  VexSign — fixed Files · Library · Home · App Store · Downloads · Settings shell
//

import Foundation

final class TabBarPreferences: ObservableObject {
    static let shared = TabBarPreferences()

    /// The primary shell is intentionally fixed. Legacy customization data is
    /// read only to preserve the user's launch-tab preference during migration.
    static let hideableTabs: [TabEnum] = []
    static let minimalTabs: [TabEnum] = []

    @Published private(set) var order: [TabEnum]
    @Published private(set) var hidden: Set<TabEnum>
    @Published private(set) var isMinimal: Bool
    @Published var defaultLaunch: TabEnum {
        didSet { _save() }
    }

    private let _key = "VexSign.tabBarPreferences"

    private struct Stored: Codable {
        var order: [String]
        var hidden: [String]
        var defaultLaunch: String
        var minimal: Bool
    }

    private init() {
        var launch = TabEnum.home
        if let data = UserDefaults.standard.data(forKey: _key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           let decoded = TabEnum(rawValue: stored.defaultLaunch) {
            launch = Self.migratedLaunchTab(decoded)
        }

        self.order = TabEnum.defaultTabs
        self.hidden = []
        self.defaultLaunch = TabEnum.defaultTabs.contains(launch) ? launch : .home
        self.isMinimal = false
        _save()
    }

    private static func migratedLaunchTab(_ tab: TabEnum) -> TabEnum {
        switch tab {
        case .sources: return .appStore
        case .logs: return .settings
        case .tweaks, .certificates: return .library
        default: return tab
        }
    }

    var orderedTabs: [TabEnum] { TabEnum.defaultTabs }
    var visibleTabs: [TabEnum] { TabEnum.defaultTabs }

    func isHideable(_ tab: TabEnum) -> Bool { false }
    func isHidden(_ tab: TabEnum) -> Bool { false }

    var resolvedLaunchTab: TabEnum {
        TabEnum.defaultTabs.contains(defaultLaunch) ? defaultLaunch : .home
    }

    // Kept as no-op compatibility methods for older callers and migrated data.
    func setHidden(_ tab: TabEnum, _ value: Bool) {
        // Primary tabs are always visible.
    }

    func setMinimal(_ value: Bool) {
        guard isMinimal else { return }
        isMinimal = false
        _save()
    }

    func move(from source: IndexSet, to destination: Int) {
        // The required primary order is immutable.
    }

    private func _save() {
        let stored = Stored(
            order: TabEnum.defaultTabs.map(\.rawValue),
            hidden: [],
            defaultLaunch: resolvedLaunchTab.rawValue,
            minimal: false
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: _key)
        }
        objectWillChange.send()
    }
}
