import Foundation

struct DiscoveryApp: Codable, Identifiable, Hashable, Sendable {
    let id: String // source + bundle ID: never silently conflates two publishers
    let source: String
    let bundleIdentifier: String
    let name: String
    let summary: String
    let developer: String
    let category: String
    let version: String
    let icon: URL?
    let download: URL?
    let updated: Date?
    let releases: Int
    var searchText: String { "\(name) \(bundleIdentifier) \(summary) \(developer) \(category)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
}
struct FeaturedApp: Identifiable { let app: DiscoveryApp; var id: String { app.id } }
struct TrendingApp: Identifiable { let app: DiscoveryApp; let score: Double; var id: String { app.id } }
struct CollectionItem: Identifiable { let id: String; let title: String; let apps: [DiscoveryApp] }
struct CategoryItem: Identifiable { let name: String; let apps: [DiscoveryApp]; var id: String { name } }

struct DiscoverySignals: Codable, Sendable {
    var favorites: Set<String> = []
    /// Local download requests, not fabricated global popularity or install counts.
    var downloads: [String: Int] = [:]
    /// Explicit user-assigned source trust, not publisher-controlled feed metadata.
    var trust: [String: Double] = [:]
}

enum DiscoveryRanking {
    static func score(_ app: DiscoveryApp, signals: DiscoverySignals, now: Date = Date()) -> Double {
        let age = max(0, now.timeIntervalSince(app.updated ?? .distantPast) / 86_400)
        let recency = exp(-age / 30)
        let frequency = min(Double(max(0, app.releases)), 24) / 24
        return log1p(Double(max(0, signals.downloads[app.id, default: 0]))) * 2
            + recency * 3 + frequency
            + min(1, max(0, signals.trust[app.source, default: 0.5])) * 2
            + (signals.favorites.contains(app.id) ? 4 : 0)
    }
}

actor DiscoveryIndex {
    private var apps: [DiscoveryApp] = []
    private var searchable: [String: String] = [:]
    func replace(_ apps: [DiscoveryApp]) {
        self.apps = apps
        searchable = Dictionary(apps.map { ($0.id, $0.searchText) }, uniquingKeysWith: { first, _ in first })
    }
    func search(_ query: String, signals: DiscoverySignals) -> [DiscoveryApp] {
        let words = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).split(whereSeparator: \.isWhitespace).map(String.init)
        let now = Date()
        return apps.filter { app in words.allSatisfy { searchable[app.id, default: ""].contains($0) } }
            .map { ($0, DiscoveryRanking.score($0, signals: signals, now: now)) }
            .sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.map(\.0)
    }
}
