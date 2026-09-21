//
//  TaskCenterView.swift
//  VexSign
//
//  The unified task center: downloads, imports, signing jobs and
//  installations in one list, with live progress, the exact failure stage,
//  retry/cancel actions and a persistent history.
//
//  Surfaced from the Downloads tab toolbar and Home.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct TaskCenterView: View {
	@ObservedObject private var center = UnifiedTaskCenter.shared
	@State private var filter: TaskFilter = .active

	enum TaskFilter: String, CaseIterable, Identifiable {
		case active = "Active"
		case failed = "Failed"
		case history = "History"
		case all = "All"
		var id: String { rawValue }
	}

	private var filteredTasks: [UnifiedTask] {
		switch filter {
		case .active: return center.tasks.filter { $0.phase.isInProgress }
		case .failed: return (center.tasks + center.history).filter { $0.phase == .failed }
		case .history: return center.history
		case .all: return center.tasks + center.history
		}
	}

	var body: some View {
		NBNavigationView(.localized("Task Center"), displayMode: .inline) {
			List {
				Section {
					Picker(.localized("Show"), selection: $filter) {
						ForEach(TaskFilter.allCases) { f in
							Text(f.rawValue).tag(f)
						}
					}
					.pickerStyle(.segmented)
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
				}

				if filteredTasks.isEmpty {
					NBContentUnavailable(
						.localized("No Tasks"),
						systemImage: "checkmark.circle",
						description: .localized("Downloads, imports, signing jobs and installations appear here with their exact stage.")
					)
					.listRowBackground(Color.clear)
				} else {
					ForEach(filteredTasks, id: \.id) { task in
						TaskRow(task: task)
					}
				}

				if !center.history.isEmpty {
					Section {
						Button(role: .destructive) {
							center.clearHistory()
						} label: {
							Label(.localized("Clear Task History"), systemImage: "trash")
						}
					} footer: {
						Text(.localized("History keeps the last 200 finished tasks (names and outcomes only)."))
					}
				}
			}
		}
	}
}

// MARK: - Row

private struct TaskRow: View {
	@ObservedObject private var center = UnifiedTaskCenter.shared
	let task: UnifiedTask

	var body: some View {
		HStack(spacing: 12) {
			ZStack {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(phaseColor.opacity(0.14))
					.frame(width: 40, height: 40)
				Image(systemName: task.kind.icon)
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(phaseColor)
			}

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					Text(task.title)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					phaseBadge
				}

				if let subtitle = task.subtitle, !subtitle.isEmpty {
					Text(subtitle)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				if let error = task.errorText, !error.isEmpty {
					// Always icon + text, never color alone.
					Label(error, systemImage: "exclamationmark.triangle.fill")
						.font(.caption2)
						.foregroundStyle(.orange)
						.lineLimit(2)
				}

				if task.phase.isInProgress && task.progress >= 0 {
					ProgressView(value: min(max(task.progress, 0), 1))
						.tint(phaseColor)
				}
			}

			Spacer(minLength: 8)

			if task.phase == .failed || task.phase == .cancelled {
				Button {
					_ = center.retry(task)
				} label: {
					Image(systemName: "arrow.clockwise")
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(Text(.localized("Retry")))
			}
		}
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(Text(verbatim: "\(task.title), \(task.phase.title)\(task.errorText.map { ", \($0)" } ?? "")"))
	}

	private var phaseColor: Color {
		switch task.phase {
		case .queued: return .secondary
		case .downloading, .extracting, .signing, .installing: return Color.userTint
		case .paused: return .orange
		case .completed: return .green
		case .failed: return .orange
		case .cancelled: return .secondary
		}
	}

	private var phaseBadge: some View {
		HStack(spacing: 3) {
			if let stage = task.failureStage, task.phase == .failed {
				Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
					.font(.system(size: 8, weight: .bold))
			}
			Text(task.phase.title)
				.font(.system(size: 10, weight: .semibold))
		}
		.padding(.horizontal, 7)
		.padding(.vertical, 2)
		.background(phaseColor.opacity(0.14), in: Capsule())
		.foregroundStyle(phaseColor)
	}
}
