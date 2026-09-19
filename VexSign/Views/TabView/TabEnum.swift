//
//  TabEnum.swift
//  vexsign
//
//  Created by VexSign TeamSign Team on 22.03.2025.
//
import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable, Codable {
	case home
	case sources
	case library
	case logs
	case tweaks
	case settings
	case certificates

	var title: String {
		switch self {
		case .home: return .localized("Home")
		case .sources:    	return .localized("Sources")
		case .library: 		return .localized("Library")
		case .logs: 		return .localized("Logs")
		case .tweaks: 		return .localized("Tweaks")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		}
	}

	var icon: String {
		switch self {
		case .home: return "house.fill"
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .logs: 		return "list.bullet.rectangle"
		case .tweaks: 		return "wrench.and.screwdriver"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		}
	}

	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .home: HomeView()
		case .sources: SourcesView()
		case .library: LibraryView()
		case .logs: LogsView()
		case .tweaks: TweaksView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}

	static var defaultTabs: [TabEnum] {
		return [
			.home,
			.sources,
			.library,
			.logs,
			.tweaks,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
