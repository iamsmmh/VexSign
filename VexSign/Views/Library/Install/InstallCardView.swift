//
//  InstallCardView.swift
//  VexSign
//
//  Created by VexSign TeamSign Team on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift

// MARK: - View: Card
struct InstallCardView: View {
	@ObservedObject var installer: AppInstaller
	var upcoming: [AnyApp] = []
	var onCancel: () -> Void
	var onPause: (() -> Void)? = nil
	var isPaused: Bool = false

	var body: some View {
		ZStack {
			InstallProgressView(app: installer.app, viewModel: installer.viewModel)
			InstallStatusView(
				app: installer.app,
				viewModel: installer.viewModel,
				upcoming: upcoming,
				onCancel: onCancel,
				onPause: onPause,
				isPaused: isPaused
			)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(NBRadius.large)
		.padding([.top, .horizontal])
		.padding(.bottom, 36)
		.ignoresSafeArea(.container, edges: .bottom)
	}
}

// MARK: - View: Status
/// Observes the status model directly
private struct InstallStatusView: View {
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	var upcoming: [AnyApp]
	var onCancel: () -> Void
	var onPause: (() -> Void)?
	var isPaused: Bool

	var body: some View {
		ZStack {
			_status()
			_button()
			_controls()

			if !upcoming.isEmpty {
				_upNext()
			}
		}
	}

	@ViewBuilder
	private func _controls() -> some View {
		ZStack {
			if !viewModel.isCompleted {
				VStack(spacing: 0) {
					Button(action: onCancel) {
						Image(systemName: "forward.fill")
							.font(.title3)
							.symbolRenderingMode(.hierarchical)
							.foregroundStyle(.secondary)
							.contentShape(Circle())
					}
					.buttonStyle(.plain)
					.padding()

					if let onPause {
						Button(action: onPause) {
							Image(systemName: isPaused ? "play.fill" : "pause.fill")
								.font(.title3)
								.symbolRenderingMode(.hierarchical)
								.foregroundStyle(.secondary)
								.contentShape(Circle())
						}
						.buttonStyle(.plain)
						.padding()
					}
				}
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}

	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}

	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if case .completed(.success) = viewModel.status,
			   let identifier = app.identifier, !identifier.isEmpty {
				Button {
					UIApplication.openApp(with: identifier)
				} label: {
					NBButton(.localized("Open"), systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}

	@ViewBuilder
	private func _upNext() -> some View {
		HStack(spacing: 8) {
			HStack(spacing: -8) {
				ForEach(upcoming.prefix(4)) { entry in
					FRAppIconView(app: entry.base, size: 22)
						.overlay {
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.strokeBorder(Color(uiColor: .secondarySystemBackground), lineWidth: 2)
						}
				}
			}

			Text(String.localized("%lld queued", arguments: upcoming.count))
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}
