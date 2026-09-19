//
//  AboutView.swift
//  VexSign
//
//  Created by the VexSign contributors.
//

import SwiftUI
import NimbleViews

// MARK: - Extension: Model
extension AboutView {
	struct CreditsModel: Codable, Hashable {
		let name: String?
		let desc: String?
		let github: String
	}
}

// MARK: - View
struct AboutView: View {
	private let _credits: [CreditsModel] = [
		.init(name: "iamsmmh", desc: "Lead developer — VexSign", github: "iamsmmh"),
		.init(name: "Samara / claration", desc: "Feather — original base (GPL-3.0)", github: "claration"),
		.init(name: "jkcoxson", desc: "idevice — AFC installation backend", github: "jkcoxson"),
		.init(name: "zhlynn", desc: "Zsign — on-device signing", github: "zhlynn"),
		.init(name: "tealbathingsuit", desc: "ElleKit — tweak injection", github: "tealbathingsuit"),
		.init(name: "kean", desc: "Nuke — image caching", github: "kean"),
		.init(name: "Lakr233", desc: "Asspp — HTTP server reference", github: "Lakr233"),
		.init(name: "nekohaxx", desc: "plistserver — install helper", github: "nekohaxx"),
		.init(name: "Contributors", desc: "Translations & pull requests", github: "iamsmmh/VexSign"),
	]

	private let _sourceURL = "https://github.com/iamsmmh/VexSign"
	private let _featherURL = "https://github.com/claration/Feather"
	private let _licenseURL = "https://github.com/iamsmmh/VexSign/blob/main/LICENSE"
	private let _authorURL = "https://github.com/iamsmmh"

	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack(spacing: 8) {
					FRAppIconView(size: 80)

					Text("VexSign")
						.font(.largeTitle)
						.bold()
						.foregroundStyle(Color.accentColor)

					Text("On-device IPA signer")
						.font(.headline)
						.foregroundStyle(.secondary)

					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text(Bundle.main.version)
					}
					.font(.footnote)
					.foregroundStyle(.secondary)

					Text("Sign · tweak · install — no PC needed.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.top, 2)
				}
			}
			.frame(maxWidth: .infinity)
			.listRowBackground(EmptyView())

			NBSection("Built on Feather") {
				VStack(alignment: .leading, spacing: 6) {
					Text("VexSign is a GPL-3.0 fork of Feather by claration.")
						.font(.subheadline)
						.bold()
					Text("Feather pioneered on-device signing on stock iOS. The signing engine, CoreData model, and large parts of the UI architecture originate from that project.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Button {
					UIApplication.open(_featherURL)
				} label: {
					Label("Feather on GitHub", systemImage: "arrow.triangle.branch")
				}
			} footer: {
				Text("All VexSign-exclusive additions are released under GPL-3.0.")
			}

			NBSection("Exclusive features") {
				VStack(alignment: .leading, spacing: 8) {
					Label("IPA Explorer — edit inside IPA", systemImage: "folder.badge.gearshape")
					Label("File Transfer Server — HTTP/WebDAV", systemImage: "antenna.radiowaves.left.and.right")
					Label("Live Activities & Dynamic Island", systemImage: "sparkles")
					Label("Auto Cleanup pipeline", systemImage: "wand.and.stars")
					Label("Batch Signing & Update All", systemImage: "square.stack.3d.up.fill")
					Label("Backup & Restore (.vexbackup)", systemImage: "externaldrive.connected.to.line.below")
					Label("Logs & File Manager", systemImage: "doc.text.magnifyingglass")
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)
			}

			NBSection(.localized("Credits")) {
				ForEach(_credits, id: \.github) { credit in
					_credit(name: credit.name, desc: credit.desc, github: credit.github)
				}
			}

			NBSection(.localized("Source & License")) {
				Button {
					UIApplication.open(_sourceURL)
				} label: {
					Label(.localized("Source Code"), systemImage: "chevron.left.forwardslash.chevron.right")
				}
				Button {
					UIApplication.open(_licenseURL)
				} label: {
					Label(.localized("License (GPL-3.0)"), systemImage: "doc.text")
				}
				Button {
					UIApplication.open(_authorURL)
				} label: {
					Label("Author on GitHub", systemImage: "person.crop.circle.fill")
				}
			} footer: {
				Text("Free software under GPL-3.0. Built on top of Feather by claration.")
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _credit(
		name: String?,
		desc: String?,
		github: String
	) -> some View {
		Button {
			UIApplication.open("https://github.com/\(github)")
		} label: {
			HStack {
				FRIconCellView(
					title: name ?? github,
					subtitle: desc ?? "",
					iconUrl: URL(string: "https://github.com/\(github).png")!,
					size: 45,
					isCircle: true
				)

				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
