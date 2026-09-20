//
//  CloudSigningView.swift
//  VexSign
//
//  Settings and configuration view for the Cloud Signing microservice bridge.
//

import SwiftUI
import NimbleViews

struct CloudSigningView: View {
	@StateObject private var _client = CloudSigningClient.shared

	var body: some View {
		Form {
			Section {
				Toggle(.localized("Enable Cloud Signing"), isOn: $_client.isEnabled)
			} footer: {
				Text(.localized("When enabled, heavy signing jobs and worker queue tasks can be offloaded to your self-hosted or managed VexSign Cloud Signing cluster."))
			}

			Section(.localized("Cluster Endpoint")) {
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
					HStack(alignment: .top, spacing: 8) {
						Image(systemName: result.contains("success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
							.foregroundStyle(result.contains("success") ? .green : .orange)
						Text(result)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}

			Section(.localized("Architecture")) {
				VStack(alignment: .leading, spacing: 6) {
					Text(.localized("Features supported:"))
						.font(.footnote.bold())
					Text("• Remote BullMQ background worker queue")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("• Isolated zsign/ldid execution sandboxes")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("• Capability-scoped OTA manifest generation")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.vertical, 4)
			}
		}
		.navigationTitle(.localized("Cloud Signing"))
		.navigationBarTitleDisplayMode(.inline)
	}
}
