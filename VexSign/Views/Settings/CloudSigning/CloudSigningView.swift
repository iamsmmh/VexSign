//
//  CloudSigningView.swift
//  VexSign
//
//  Settings and configuration view for the Cloud Signing microservice bridge.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct CloudSigningView: View {
	@StateObject private var _client = CloudSigningClient.shared

	var body: some View {
		Form {
			_enableSection
			_endpointSection
			_connectionSection
			_architectureSection
		}
		.navigationTitle(.localized("Cloud Signing"))
		.navigationBarTitleDisplayMode(.inline)
	}

	// MARK: - Sections

	private var _enableSection: some View {
		NBSection(.localized("Status")) {
			Toggle(.localized("Enable Cloud Signing"), isOn: $_client.isEnabled)
		} footer: {
			Text(.localized("When enabled, heavy signing jobs and worker queue tasks can be offloaded to your self-hosted or managed VexSign Cloud Signing cluster."))
		}
	}

	private var _endpointSection: some View {
		NBSection(.localized("Cluster Endpoint")) {
			HStack {
				Text(.localized("Endpoint"))
					.foregroundStyle(.secondary)
					.frame(width: 80, alignment: .leading)
				TextField("https://cloud.vexsign.app", text: $_client.serverURLString)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
			}

			HStack {
				Text(.localized("API Key"))
					.foregroundStyle(.secondary)
					.frame(width: 80, alignment: .leading)
				SecureField(.localized("Optional Bearer Token"), text: $_client.apiKey)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
			}
		} footer: {
			Text(.localized("The base URL of your Fastify cloud-signing instance, along with any configured authentication token."))
		}
	}

	private var _connectionSection: some View {
		Section {
			Button {
				Task { await _client.testConnection() }
			} label: {
				HStack {
					Text(.localized("Test Connection"))
					Spacer()
					if _client.isTesting {
						ProgressView()
					}
				}
			}
			.disabled(_client.isTesting)

			if let result = _client.lastTestResult {
				_resultRow(result)
			}
		}
	}

	private func _resultRow(_ result: String) -> some View {
		let succeeded = result.contains("success")
		let symbol = succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
		let tint: Color = succeeded ? .green : .orange

		return HStack(alignment: .top, spacing: 8) {
			Image(systemName: symbol)
				.foregroundStyle(tint)
			Text(result)
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private var _architectureSection: some View {
		NBSection(.localized("Architecture")) {
			VStack(alignment: .leading, spacing: 6) {
				Text(.localized("Features supported:"))
					.font(.footnote.bold())
				_featureRow("Remote BullMQ background worker queue")
				_featureRow("Isolated zsign/ldid execution sandboxes")
				_featureRow("Capability-scoped OTA manifest generation")
			}
			.padding(.vertical, 4)
		}
	}

	private func _featureRow(_ text: String) -> some View {
		Text(verbatim: "• \(text)")
			.font(.caption)
			.foregroundStyle(.secondary)
	}
}
