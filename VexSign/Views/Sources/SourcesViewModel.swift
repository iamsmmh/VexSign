//
//  SourcesViewModel.swift
//  VexSign
//
//  Created by VexSign TeamSign Team on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON
import OSLog

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()

	typealias RepositoryDataHandler = Result<ASRepository, Error>

	private let _dataService = NBFetchService()

	/// `true` when no load is in progress (idle).
	@Published var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]

	/// The single in-flight load. All loads are serialized through this.
	private var currentFetchTask: Task<Void, Never>?
	/// Monotonic token identifying the active load (Task isn't Equatable).
	private var fetchGeneration = 0
	/// Source URLs of the last completed load; skips re-fetching an identical set.
	private var lastLoadedKey: Set<String>?
    private var lastLoadedAt: Date?
	private var backgroundTaskManager: BackgroundTaskManager?

	private func key(for sources: [AltSource]) -> Set<String> {
		Set(sources.compactMap { $0.sourceURL?.absoluteString })
	}

	/// Reset the loading state - useful when app returns from background
	@MainActor
	func resetLoadingState() {
		currentFetchTask?.cancel()
		currentFetchTask = nil
		fetchGeneration += 1
		isFinished = true
		lastLoadedKey = nil
		backgroundTaskManager?.stop()
		backgroundTaskManager = nil
	}

	/// Loads every source's repository. Concurrent calls are serialized and coalesced.
	@MainActor
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		await fetchSources(Array(sources), refresh: refresh, batchSize: batchSize)
	}

	/// Array-based overload for callers without a `FetchedResults` (Update All, background automation).
	@MainActor
	func fetchSources(_ sourcesArray: [AltSource], refresh: Bool = false, batchSize: Int = 4) async {
		let newKey = key(for: sourcesArray)

		// Coalesce: wait out any in-flight load. The task self-clears in its own
		// defer so awaiters exit instead of busy-spinning the main actor (0x8BADF00D).
		while let running = currentFetchTask {
			await running.value
		}

		// Same source set already loaded — skip (pull-to-refresh bypasses this).
		if !refresh, newKey == lastLoadedKey, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < RepositorySyncEngine.refreshInterval {
			return
		}

		fetchGeneration += 1
		let generation = fetchGeneration
		let task = Task {
			defer {
				// Self-clear exactly once, unless a newer load already replaced us.
				if generation == self.fetchGeneration {
					self.currentFetchTask = nil
				}
			}
			await self._performFetch(sourcesArray, key: newKey, batchSize: batchSize)
		}
		currentFetchTask = task
		await task.value
	}

	@MainActor
	private func _performFetch(_ sourcesArray: [AltSource], key: Set<String>, batchSize: Int) async {
		isFinished = false

		if backgroundTaskManager == nil {
			backgroundTaskManager = BackgroundTaskManager(
				taskName: "SourcesViewModel",
				expirationTitle: "Loading repositories",
				expirationBody: "Repository loading will continue when you reopen the app"
			)
			backgroundTaskManager?.start()
		}

		defer {
			lastLoadedKey = key
			isFinished = true
			backgroundTaskManager?.stop()
			backgroundTaskManager = nil
		}

		// Read CoreData (AltSource) fields on the main actor — it's not thread-safe.
		struct FetchItem {
			let source: AltSource
			let url: URL
			let headers: [String: String]
			let isPremium: Bool
		}

		let items: [FetchItem] = sourcesArray.compactMap { source in
			guard let url = source.sourceURL else {
				Logger.misc.error("Source has no URL: \(source.name ?? "Unknown", privacy: .public)")
				return nil
			}
			var headers = VexSignAPI.authHeaders(for: url)
			#if canImport(AltSourceKit)
			if !EsignSourceKey.customApiKey.isEmpty, headers["X-API-Key"] == nil {
				headers["X-API-Key"] = EsignSourceKey.customApiKey
			}
			#endif
			return FetchItem(
				source: source,
				url: VexSignAPI.catalogURL(for: url),
				headers: headers,
				isPremium: VexSignAPI.isPremiumSource(url)
			)
		}

		Logger.misc.info("fetchSources START: \(items.count, privacy: .public) sources")

		let service = _dataService
		// Publish into a working copy cumulatively so `sources` is never blanked mid-load.
		let activeSources = Set(sourcesArray)
        var working = self.sources.filter { activeSources.contains($0.key) }
        var successes = 0

		for startIndex in stride(from: 0, to: items.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, items.count)
			let batch = Array(items[startIndex..<endIndex])

			// Child tasks touch only Sendable values, never the NSManagedObject.
			let fetched: [(Int, ASRepository?)] = await withTaskGroup(of: (Int, ASRepository?).self) { group in
				for (offset, item) in batch.enumerated() {
					let globalIndex = startIndex + offset
					let url = item.url
					let headers = item.headers
					let isPremium = item.isPremium

					group.addTask {
						let repo: ASRepository? = await withCheckedContinuation { continuation in
							service.fetch(from: url, headers: headers) { (result: RepositoryDataHandler) in
								switch result {
								case .success(let repo):
									continuation.resume(returning: repo)
								case .failure(let error):
									Logger.misc.error("Source fetch FAILED\(isPremium ? " [PREMIUM]" : "", privacy: .public) \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
									continuation.resume(returning: nil)
								}
							}
						}
						return (globalIndex, repo)
					}
				}

				var collected: [(Int, ASRepository?)] = []
				for await pair in group {
					collected.append(pair)
				}
				return collected
			}

			for (idx, repo) in fetched {
				let item = items[idx]
				let id = item.source.identifier ?? item.url.absoluteString
				if let repo {
                    successes += 1
                    working[item.source] = repo
					SourcePreferences.recordFetch(id: id, error: nil)
				} else {
					SourcePreferences.recordFetch(id: id, error: .localized("Couldn't load this source"))
				}
			}

			// Publish progress (grows, never empties).
			self.sources = working
		}

        if successes == items.count { lastLoadedAt = Date() }
        else { lastLoadedAt = nil }
        Logger.misc.info("fetchSources DONE: \(working.count, privacy: .public)/\(items.count, privacy: .public) loaded")
	}
}
