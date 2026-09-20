//
//  AboutView.swift
//  VexSign — ported from Ksign with patch notes, hero header, credits & acknowledgements.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

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
		.init(name: "Nyasami", desc: "Developer — Ksign (Esign/Feather hybrid)", github: "Nyasami"),
		.init(name: "Samara / claration", desc: "Feather — original base (GPL-3.0)", github: "claration"),
		.init(name: "jkcoxson", desc: "idevice — AFC installation backend", github: "jkcoxson"),
		.init(name: "zhlynn", desc: "Zsign — on-device signing", github: "zhlynn"),
		.init(name: "tealbathingsuit", desc: "ElleKit — tweak injection", github: "tealbathingsuit"),
		.init(name: "kean", desc: "Nuke — image caching", github: "kean"),
		.init(name: "Lakr233", desc: "Asspp — HTTP server reference", github: "Lakr233"),
		.init(name: "nekohaxx", desc: "plistserver — install helper", github: "nekohaxx"),
		.init(name: "Contributors", desc: "Translations & community pull requests", github: "iamsmmh/VexSign"),
	]

	private let _sourceURL = "https://github.com/iamsmmh/VexSign"
	private let _featherURL = "https://github.com/claration/Feather"
	private let _ksignURL = "https://github.com/Nyasami/Ksign"
	private let _licenseURL = "https://github.com/iamsmmh/VexSign/blob/main/LICENSE"
	private let _authorURL = "https://github.com/iamsmmh"

	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack(spacing: 8) {
					FRAppIconView(size: 80)

					Text(Bundle.main.name.isEmpty ? "VexSign" : Bundle.main.name)
						.font(.largeTitle)
						.bold()
						.foregroundStyle(Color.accentColor)

					Text("On-device IPA signer & sideloading platform")
						.font(.headline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)

					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text(Bundle.main.version)
						if !Bundle.main.buildNumber.isEmpty {
							Text("(\(Bundle.main.buildNumber))")
						}
					}
					.font(.footnote)
					.foregroundStyle(.secondary)

					Button {
						_showPatchNotes()
					} label: {
						HStack(spacing: 6) {
							Image(systemName: "sparkles")
							Text("Show patch notes")
						}
						.font(.footnote.weight(.semibold))
						.padding(.horizontal, 14)
						.padding(.vertical, 6)
						.background(Color.accentColor.opacity(0.12), in: Capsule())
						.foregroundStyle(Color.accentColor)
					}
					.buttonStyle(.plain)
					.padding(.top, 4)

					Text("Sign · tweak · install — no PC needed.")
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.top, 2)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 6)
			}
			.listRowBackground(EmptyView())

			NBSection("Special thanks!") {
				Text(.localized("This couldn't have been done without the original Feather and Ksign devs! ❤️"))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.padding(.vertical, 2)
			}

			NBSection("Built on Feather & Ksign") {
				VStack(alignment: .leading, spacing: 6) {
					Text("VexSign is inspired by Ksign and built on top of Feather by claration.")
						.font(.subheadline)
						.bold()
					Text("Feather and Ksign pioneered modern on-device signing, tab workflows and tweak injection on stock iOS.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Button {
					UIApplication.open(_ksignURL)
				} label: {
					Label("Ksign on GitHub", systemImage: "arrow.triangle.branch")
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
					Label("Apple Official App Store redesign with merged Sources", systemImage: "bag.fill")
					Label("Ksign-style Files tab with storage gauge & quick access", systemImage: "folder.fill")
					Label("Dedicated Downloads tab with background downloader", systemImage: "arrow.down.circle.fill")
					Label("Single Back Navigation Bar throughout", systemImage: "chevron.left")
					Label("IPA Explorer — edit inside IPA files", systemImage: "folder.badge.gearshape")
					Label("File Transfer Server — HTTP & WebDAV", systemImage: "antenna.radiowaves.left.and.right")
					Label("Live Activities & Dynamic Island tracking", systemImage: "sparkles")
					Label("Auto Cleanup pipeline & Storage Manager", systemImage: "wand.and.stars")
					Label("Batch Signing & Update All across sources", systemImage: "square.stack.3d.up.fill")
					Label("Backup & Restore (.vexbackup)", systemImage: "externaldrive.connected.to.line.below")
					Label("Activity Logs moved to Settings", systemImage: "text.alignleft")
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
				Text(Bundle.main.bundleIdentifier ?? "com.vexsign.app")
			}
		}
	}

	private func _showPatchNotes() {
		UIAlertController.showAlertWithOk(
			title: .localized("From VexSign Team, Version \(Bundle.main.version)"),
			message: .localized("This version introduces:\n\n• Redesigned Apple Official App Store tab with merged Sources\n• Ksign-style Files tab with storage ring & Quick Access folders\n• Dedicated Downloads tab with active progress & finished IPAs management\n• Single Back Navigation Bar throughout the app (no duplicate headers)\n• Activity Logs moved cleanly to Settings\n• App About ported from Ksign with patch notes & acknowledgements\n• Fully functional tabs: Files, Library, Home, App Store, Downloads, Settings\n• Seamless background downloading and on-device IPA signing"),
			isCancel: true
		)
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
