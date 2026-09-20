//
//  WebToolsView.swift
//  VexSign
//
//  Ecosystem → Web Tools. The three browser tools the backend serves: a
//  repository creator, a certificate status checker and a UDID grabber. They are
//  the same code whether you run the server yourself or use a hosted deployment —
//  this screen is only a launcher plus the address, so nothing about them is
//  duplicated inside the app.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct WebToolsView: View {
	static let baseURLKey = "VexSign.webTools.baseURL"

	@AppStorage(WebToolsView.baseURLKey) private var _baseURL: String = ""

	private struct Tool: Identifiable {
		let id: String
		let path: String
		let title: String
		let detail: String
		let systemImage: String
	}

	private let _tools: [Tool] = [
		Tool(
			id: "repo",
			path: "/tools/repo-creator",
			title: .localized("Repository Creator"),
			detail: .localized("Build, validate and export a source feed, plus OTA manifests. Exports to your device — nothing is uploaded."),
			systemImage: "shippingbox"
		),
		Tool(
			id: "cert",
			path: "/tools/cert-check",
			title: .localized("Certificate Status Checker"),
			detail: .localized("Read expiry, team, entitlements and device scope from a provisioning profile. It never accepts a .p12 or a password."),
			systemImage: "checkmark.shield"
		),
		Tool(
			id: "udid",
			path: "/tools/udid",
			title: .localized("UDID Grabber"),
			detail: .localized("Install a one-time enrolment profile and read the UDID. Sessions expire after 15 minutes and are never stored."),
			systemImage: "iphone"
		)
	]

	var body: some View {
		NBList(.localized("Web Tools")) {
			_addressSection
			_toolsSection
			_honestySection
		}
	}

	// MARK: Address

	@ViewBuilder
	private var _addressSection: some View {
		Section {
			TextField(.localized("https://your-vexsign-server.example"), text: $_baseURL)
				.keyboardType(.URL)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
		} header: {
			Text(.localized("Server"))
		} footer: {
			Text(.localized("The address of a VexSign backend (the one in `server/`). Every deployment serves these tools under /tools."))
		}
	}

	// MARK: Tools

	@ViewBuilder
	private var _toolsSection: some View {
		NBSection(.localized("Tools")) {
			ForEach(_tools) { tool in
				_row(tool)
			}
		}
	}

	@ViewBuilder
	private func _row(_ tool: Tool) -> some View {
		let url = _url(for: tool)

		Button {
			if let url {
				UIApplication.open(url)
			} else {
				// No server configured: hand over the path so the user can paste it
				// onto whatever host they run.
				UIPasteboard.general.string = tool.path
				Toast.info(.localized("Server address not set — copied the path instead"), systemImage: "doc.on.doc")
			}
		} label: {
			Label {
				VStack(alignment: .leading, spacing: 2) {
					Text(tool.title)
					Text(tool.detail)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			} icon: {
				Image(systemName: tool.systemImage)
					.foregroundStyle(url == nil ? Color.secondary : Color.accentColor)
			}
		}
		.disabled(false)
	}

	// MARK: Honesty

	@ViewBuilder
	private var _honestySection: some View {
		Section {
			Label {
				Text(.localized("These tools run on the server, not on your device. They do not sign anything, never see a private key, and the repository creator does not host your IPAs — it hands you a file to upload yourself."))
					.font(.caption)
					.foregroundStyle(.secondary)
			} icon: {
				Image(systemName: "info.circle")
					.foregroundStyle(.secondary)
			}
		}
	}

	// MARK: Helpers

	private func _url(for tool: Tool) -> URL? {
		let base = _baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !base.isEmpty else { return nil }
		let normalized = base.hasSuffix("/") ? String(base.dropLast()) : base
		return URL(string: normalized + tool.path)
	}

}
