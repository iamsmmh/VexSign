//
//  SettingsDonationCellView.swift
//  VexSign
//
//  Created by VexSign Team on 19.09.2026.
//
#if !NIGHTLY && !DEBUG
import SwiftUI
import NimbleViews
import NimbleExtensions

struct SettingsDonationCellView: View {
	var site: String

	var body: some View {
		Section {
			VStack(spacing: 14) {
				Image(systemName: "star.fill")
					.font(.system(size: 54))
					.foregroundStyle(Color.accentColor)
					.padding(.top, 12)

				VStack(spacing: 4) {
					Text("VexSign")
						.font(.title3.bold())
					Text("On-device IPA signer")
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
					Text("IPA Explorer • File Transfer • Live Activities • Auto Cleanup • Batch Signing")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.top, 2)
				}

				Button {
					UIApplication.open(site)
				} label: {
					Text("⭐ Star on GitHub")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 28)
						.frame(height: 42)
						.background(Color.accentColor, in: Capsule())
				}
				.buttonStyle(.plain)
				.padding(.top, 4)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
		}
	}
}
#endif
