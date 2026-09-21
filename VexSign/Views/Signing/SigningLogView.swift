//
//  SigningLogView.swift
//  VexSign
//
//  Created by VexSign Team
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct SigningLogView: View {
	@ObservedObject private var _log = SigningLog.shared

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Signing Logs"), displayMode: .inline) {
			LogConsoleView(entries: _log.lines, showCategory: true, style: .transparent)
				.background(Color(uiColor: .systemBackground))
				.overlay {
					if _log.lines.isEmpty {
						Text(.localized("No logs yet"))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				.toolbar {
					NBToolbarButton(role: .close)
			NBToolbarButton(
					.localized("Copy"),
					style: .text,
					placement: .topBarLeading,
					isDisabled: _log.lines.isEmpty
				) {
					// This sheet shows one signing run, so it exports one signing run — the Logs
					// tab is where the history lives.
					UIPasteboard.general.string = _log.exportText(_log.lines)
					Toast.success(.localized("Copied"))
				}
				}
		}
	}
}
