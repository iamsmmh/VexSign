//
//  TabBarPreferences.swift
//  VexSign — Files · Library · Home · App Store · Downloads · Settings
//

import Foundation

final class TabBarPreferences: ObservableObject {
    static let shared = TabBarPreferences()

    /// Home & Settings are permanent; everything else can be hidden.
    static let hideableTabs: [TabEnum] = [.files, .library, .appStore, .downloads]

    /// Minimal keeps just Home + Settings
    static let minimalTabs: [TabEnum] = [.home, .settings]

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
        init(order: [String], hidden: [String], defaultLaunch: String, minimal: Bool) {
            self.order = order; self.hidden = hidden; self.defaultLaunch = defaultLaunch; self.minimal = minimal
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
            defaultLaunch = try c.decodeIfPresent(String.self, forKey: .defaultLaunch) ?? TabEnum.home.rawValue
            minimal = try c.decodeIfPresent(Bool.self, forKey: .minimal) ?? false
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        var loadedOrder = TabEnum.defaultTabs
        var loadedHidden: Set<TabEnum> = []
        var loadedLaunch: TabEnum = .home
        var loadedMinimal = false

        if let data = defaults.data(forKey: _key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            var decoded = stored.order.compactMap { TabEnum(rawValue: $0) }
            // Migrate old Sources → new App Store
            if decoded.contains(.sources) && !decoded.contains(.appStore) {
                if let idx = decoded.firstIndex(of: .sources) {
                    decoded[idx] = .appStore
                }
            }
            var sanitized: [TabEnum] = []
            for tab in decoded where TabEnum.defaultTabs.contains(tab) && !sanitized.contains(tab) {
                sanitized.append(tab)
            }
            for tab in TabEnum.defaultTabs where !sanitized.contains(tab) {
                sanitized.append(tab)
            }
            loadedOrder = sanitized
            loadedHidden = Set(stored.hidden.compactMap { TabEnum(rawValue: $0) })
            loadedLaunch = TabEnum(rawValue: stored.defaultLaunch) ?? .home
            // If old launch was Sources, map to App Store
            if loadedLaunch == .sources { loadedLaunch = .appStore }
            if loadedLaunch == .logs { loadedLaunch = .settings }
            if loadedLaunch == .tweaks { loadedLaunch = .library }
            loadedMinimal = stored.minimal
        } else if defaults.object(forKey: "VexSign.showTweaksTab") != nil,
                  defaults.bool(forKey: "VexSign.showTweaksTab") == false {
            loadedHidden = []
        }

        self.order = loadedOrder
        self.hidden = loadedHidden
        self.defaultLaunch = loadedLaunch
        self.isMinimal = loadedMinimal
        _normalize()
    }

    var orderedTabs: [TabEnum] {
        var result = order.filter { TabEnum.defaultTabs.contains($0) }
        for tab in TabEnum.defaultTabs where !result.contains(tab) {
            result.append(tab)
        }
        return result
    }

    var visibleTabs: [TabEnum] {
        guard !isMinimal else {
            return orderedTabs.filter { Self.minimalTabs.contains($0) }
        }
        return orderedTabs.filter { !hidden.contains($0) }
    }

    func isHideable(_ tab: TabEnum) -> Bool { Self.hideableTabs.contains(tab) }
    func isHidden(_ tab: TabEnum) -> Bool { hidden.contains(tab) }

    var resolvedLaunchTab: TabEnum {
        visibleTabs.contains(defaultLaunch) ? defaultLaunch : (visibleTabs.first ?? .home)
    }

    func setHidden(_ tab: TabEnum, _ value: Bool) {
        guard isHideable(tab) else { return }
        if value { hidden.insert(tab) } else { hidden.remove(tab) }
        _normalize(); _save()
    }

    func setMinimal(_ value: Bool) {
        guard isMinimal != value else { return }
        isMinimal = value; _normalize(); _save()
    }

    func move(from source: IndexSet, to destination: Int) {
        var current = orderedTabs
        current.move(fromOffsets: source, toOffset: destination)
        order = current; _save()
    }

    private func _normalize() {
        order = orderedTabs
        hidden = hidden.intersection(Self.hideableTabs)
        if !visibleTabs.contains(defaultLaunch) {
            defaultLaunch = visibleTabs.first ?? .home
        }
    }

    private func _save() {
        let stored = Stored(order: orderedTabs.map { $0.rawValue }, hidden: hidden.map { $0.rawValue }, defaultLaunch: defaultLaunch.rawValue, minimal: isMinimal)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: _key)
        }
        objectWillChange.send()
    }
}
