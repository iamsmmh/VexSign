//
//  CertificateCellView.swift
//  VexSign
//
//  Created by VexSign TeamSign Team on 16.04.2025.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct CertificatesCellView: View {
	@State var data: Certificate?
	
	@ObservedObject var cert: CertificatePair
	@ObservedObject private var statusManager = CertificateStatusManager.shared

	// MARK: Body
	var body: some View {
		VStack(spacing: 6) {
			let title = {
				var title = cert.nickname ?? data?.Name ?? .localized("Unknown")
				
				if let getTaskAllow = data?.Entitlements?["get-task-allow"]?.value as? Bool, getTaskAllow == true {
					title = "🐞 \(title)"
				}
				
				return title
			}()
			
			NBTitleWithSubtitleView(
				title: title,
				subtitle: data?.AppIDName ?? .localized("Unknown")
			)
			
			_certInfoPill(data: cert)
		}
		.frame(height: 80)
		.contentTransition(.opacity)
		.frame(maxWidth: .infinity, alignment: .leading)
		.onAppear {
			withAnimation {
				data = Storage.shared.getProvisionFileDecoded(for: cert)
			}
		}
		.task(id: cert.uuid ?? cert.objectID.uriRepresentation().absoluteString) {
			statusManager.refreshStatusIfNeeded(for: cert)
		}
	}
}

// MARK: - Extension: View
extension CertificatesCellView {
	@ViewBuilder
	private func _certInfoPill(data: CertificatePair) -> some View {
		let pillItems = _buildPills(from: data)
		HStack(spacing: 6) {
			ForEach(pillItems.indices, id: \.hashValue) { index in
				let pill = pillItems[index]
				NBPillView(
					title: pill.title,
					icon: pill.icon,
					color: pill.color,
					index: index,
					count: pillItems.count
				)
			}
		}
	}
	
	private func _buildPills(from cert: CertificatePair) -> [NBPillItem] {
		var pills: [NBPillItem] = []
		let status = statusManager.effectiveStatus(for: cert)
		let title = statusManager.effectiveStatusTitle(for: cert)

		pills.append(
			NBPillItem(
				title: title,
				icon: status.icon,
				color: status.color
			)
		)

		// PPQLess (green) = distribution profile Apple can't revoke through PPQ.
		// PPQ (orange) = development profile: revocable, but the only kind JIT works on.
		let ppq = cert.ppqBadge
		pills.append(NBPillItem(title: ppq.title, icon: ppq.icon, color: ppq.color))

		if let info = cert.expiration?.expirationInfo() {
			pills.append(NBPillItem(
				title: info.formatted,
				icon: info.icon,
				color: info.color
			))
		}
		
		return pills
	}
}
