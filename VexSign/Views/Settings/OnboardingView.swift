//
//  OnboardingView.swift
//  VexSign
//
//  First-launch wizard: what VexSign is, import a certificate, pick install method.
//

import SwiftUI
import NimbleViews
import IDeviceSwift

struct OnboardingView: View {
	@Environment(\.dismiss) private var dismiss
	@AppStorage("VexSign.onboardingCompleted") private var _completed = false
	@AppStorage("VexSign.installationMethod") private var _installMethod = 0
	@State private var _page = 0
	@State private var _isAddingCert = false

	var body: some View {
		NBNavigationView(.localized("Welcome")) {
			TabView(selection: $_page) {
				_pageWelcome.tag(0)
				_pageCertificate.tag(1)
				_pageInstall.tag(2)
			}
			.tabViewStyle(.page(indexDisplayMode: .always))
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(_page == 2 ? .localized("Done") : .localized("Next")) {
						if _page < 2 {
							_page += 1
						} else {
							_completed = true
							dismiss()
						}
					}
				}
				if _page > 0 {
					ToolbarItem(placement: .topBarLeading) {
						Button(.localized("Back")) { _page -= 1 }
					}
				}
			}
			.sheet(isPresented: $_isAddingCert) {
				CertificatesAddView()
					.presentationDetents([.medium])
			}
		}
		.interactiveDismissDisabled(!_completed && _page < 2)
	}

	private var _pageWelcome: some View {
		VStack(spacing: 16) {
			Image(systemName: "signature")
				.font(.system(size: 48))
				.foregroundStyle(Color.accentColor)
			Text(.localized("Sign and install apps on this device."))
				.font(.title2.weight(.semibold))
				.multilineTextAlignment(.center)
			Text(.localized("VexSign uses your certificate to sign IPAs, then installs them over the local server or a pairing file. Nothing is uploaded."))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Spacer()
		}
		.padding(28)
	}

	private var _pageCertificate: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(.localized("Import a certificate"))
				.font(.title2.weight(.semibold))
			Text(.localized("A .p12 and .mobileprovision pair is required to sign. You can skip this and import later from Settings → Certificates."))
				.foregroundStyle(.secondary)
			Button {
				_isAddingCert = true
			} label: {
				Label(.localized("Import Certificate"), systemImage: "plus")
			}
			.buttonStyle(.borderedProminent)
			Spacer()
		}
		.padding(28)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var _pageInstall: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(.localized("How should apps install?"))
				.font(.title2.weight(.semibold))
			PicketInstall(method: $_installMethod)
			Text(.localized("Server install works without a computer. Pairing (idevice) needs a lockdownd pairing file and a VPN, and installs more like a USB sideload."))
				.font(.footnote)
				.foregroundStyle(.secondary)
			Spacer()
		}
		.padding(28)
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct PicketInstall: View {
	@Binding var method: Int

	var body: some View {
		VStack(spacing: 10) {
			_row(0, title: .localized("Local Server"), detail: .localized("itms-services over HTTPS. Works on any device."))
			_row(1, title: .localized("Pairing / idevice"), detail: .localized("Needs a pairing file. Fastest once set up."))
		}
	}

	private func _row(_ value: Int, title: String, detail: String) -> some View {
		Button {
			method = value
		} label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(title).font(.body.weight(.medium))
					Text(detail).font(.caption).foregroundStyle(.secondary)
				}
				Spacer()
				if method == value {
					Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
				}
			}
			.padding()
			.background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
		.buttonStyle(.plain)
	}
}
