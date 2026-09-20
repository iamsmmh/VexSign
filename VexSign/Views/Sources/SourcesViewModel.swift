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

	/// Sources currently shown from the offline snapshot cache rather than a
	/// fresh load (offline / failing). Browsed data stays available and is
	/// clearly marked stale.
	@Published private(set) var staleSourceIDs: Set<String> = []

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

	/// Stable identifier for a source record (falls back to its URL).
	private static func _id(for source: AltSource, fallbackURL: URL? = nil) -> String {
		source.identifier ?? fallbackURL?.absoluteString ?? source.sourceURL?.absoluteString ?? source.objectID.uriRepresentation().absoluteString
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

	/// True when the source is currently shown from the offline snapshot
	/// cache rather than a fresh load.
	func isStale(_ source: AltSource) -> Bool {
		staleSourceIDs.contains(Self._id(for: source))
	}

	/// Drops every cached entry whose Core Data object no longer exists
	/// (e.g. the repository was deleted while a refresh was running). Without
	/// this, iterating the dictionary after a deletion touches a faulted
	/// managed object and can crash the App Store tab.
	@MainActor
	func evictDeletedSources(valid sources: [AltSource]) {
		let validSet = Set(sources)
		let doomed = self.sources.keys.filter { !$0.isValid || $0.isDeleted || !validSet.contains($0) }
		guard !doomed.isEmpty else { return }
		for source in doomed {
			self.sources.removeValue(forKey: source)
		}
		let doomedIDs = Set(doomed.map { Self._id(for: $0) })
		staleSourceIDs.subtract(doomedIDs)
		for id in doomedIDs {
			SourcePreferences.removeAllData(for: id)
			RepositorySnapshotCache.remove(identifier: id)
		}
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
			let identifier: String
			let url: URL
			let headers: [String: String]
			let isPremium: Bool
		}

		var items: [FetchItem] = []
		var transportBlocked: [(source: AltSource, identifier: String)] = []
		for source in sourcesArray {
			guard let url = source.sourceURL else {
				Logger.misc.error("Source has no URL: \(source.name ?? "Unknown", privacy: .public)")
				continue
			}
			// Transport policy: an insecure HTTP repository is not refreshed
			// (and its traffic not sent) unless the user opted in. The catalog
			// — if cached — keeps serving as clearly-marked stale data.
			do {
				try SourceURLPolicy.validate(url)
			} catch {
				let id = Self._id(for: source, fallbackURL: url)
				SourcePreferences.recordFetch(id: id, error: error.localizedDescription)
				Logger.security.warning("Skipping refresh of insecure repository: \(url.absoluteString, privacy: .public)")
				transportBlocked.append((source, id))
				continue
			}
			var headers = VexSignAPI.authHeaders(for: url)
			#if canImport(AltSourceKit)
			if !EsignSourceKey.customApiKey.isEmpty, headers["X-API-Key"] == nil {
				headers["X-API-Key"] = EsignSourceKey.customApiKey
			}
			#endif
			items.append(FetchItem(
				source: source,
				identifier: Self._id(for: source, fallbackURL: url),
				url: VexSignAPI.catalogURL(for: url),
				headers: headers,
				isPremium: VexSignAPI.isPremiumSource(url)
			))
		}

		Logger.misc.info("fetchSources START: \(items.count, privacy: .public) sources")

		// Offline prefill: any source with no in-memory catalog gets its last
		// known-good snapshot immediately, so the store is browsable while the
		// refresh runs (and entirely offline after a cold launch).
		var working = self.sources.filter { sourcesArray.contains($0.key) }
		for item in items where working[item.source] == nil {
			if let cached = RepositorySnapshotCache.load(identifier: item.identifier) {
				cached.repository.sourceURL = item.source.sourceURL
				working[item.source] = cached.repository
				staleSourceIDs.insert(item.identifier)
			}
		}
		// Sources blocked by the transport policy keep their cached catalog
		// too — browsing works, refreshes simply don't run for them.
		for blocked in transportBlocked where working[blocked.source] == nil {
			if let cached = RepositorySnapshotCache.load(identifier: blocked.identifier) {
				cached.repository.sourceURL = blocked.source.sourceURL
				working[blocked.source] = cached.repository
			}
			if working[blocked.source] != nil {
				staleSourceIDs.insert(blocked.identifier)
			}
		}
		if !working.isEmpty {
			self.sources = working
		}

		// A rate-limited source is skipped entirely this round: hammering it
		// again only extends the window.
		let rateLimitedIDs = Set(items.filter { SourcePreferences.health(for: $0.identifier).isRateLimited }.map { $0.identifier })
		let fetchable = items.filter { !rateLimitedIDs.contains($0.identifier) }
		for item in items where rateLimitedIDs.contains(item.identifier) {
			Logger.misc.warning("Source rate-limited, skipping this refresh: \(item.identifier, privacy: .public)")
		}

		let service = _dataService
		var successes = 0

		/// Result of one raw fetch, with the real error preserved so the
		/// health dashboard can show it (and so HTTP 429 can be detected).
		struct FetchOutcome {
			let payload: Data?
			let errorMessage: String?
			let rateLimited: Bool
		}

		for startIndex in stride(from: 0, to: fetchable.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, fetchable.count)
			let batch = Array(fetchable[startIndex..<endIndex])

			// Child tasks touch only Sendable values, never the NSManagedObject.
			let fetched: [(Int, FetchOutcome)] = await withTaskGroup(of: (Int, FetchOutcome).self) { group in
				for (offset, item) in batch.enumerated() {
					let globalIndex = startIndex + offset
					let url = item.url
					let headers = item.headers

					group.addTask {
						let outcome: FetchOutcome = await withCheckedContinuation { continuation in
							service.fetchRaw(from: url, headers: headers) { (result: Result<Data, Error>) in
								switch result {
								case .success(let data):
									continuation.resume(returning: FetchOutcome(payload: data, errorMessage: nil, rateLimited: false))
								case .failure(let error):
									Logger.misc.error("Source fetch FAILED \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
									var rateLimited = false
									if case NBFetchService.NBFetchServiceError.httpError(429) = error {
										rateLimited = true
									}
									continuation.resume(returning: FetchOutcome(payload: nil, errorMessage: error.localizedDescription, rateLimited: rateLimited))
								}
							}
						}
						return (globalIndex, outcome)
					}
				}

				var collected: [(Int, FetchOutcome)] = []
				for await pair in group {
					collected.append(pair)
				}
				return collected
			}

			for (idx, outcome) in fetched {
				let item = fetchable[idx]
				if let payload = outcome.payload, !payload.isEmpty {
					var repo: ASRepository?
					do {
						repo = try JSONDecoder().decode(ASRepository.self, from: payload)
					} catch {
						Logger.misc.error("Source decode FAILED \(item.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
					}

					if var decoded = repo {
						successes += 1
						// Repositories are published as bare JSON and carry no
						// self-reference, so record where this one came from.
						decoded.sourceURL = item.source.sourceURL
						working[item.source] = decoded
						staleSourceIDs.remove(item.identifier)
						SourcePreferences.recordFetch(id: item.identifier, error: nil)
						RepositorySnapshotCache.store(
							identifier: item.identifier,
							sourceURL: item.source.sourceURL,
							payload: payload
						)
					} else {
						// Invalid repository JSON: keep the last-known-good entry
						// (already in `working`) and record the real reason.
						SourcePreferences.recordFetch(
							id: item.identifier,
							error: .localized("Invalid repository data"),
							rateLimited: false
						)
						if working[item.source] != nil {
							staleSourceIDs.insert(item.identifier)
						}
					}
				} else {
					// Offline / server error / rate limited. The real message
					// goes into the health record; the catalog (if any) stays
					// as clearly-marked stale data.
					SourcePreferences.recordFetch(
						id: item.identifier,
						error: outcome.errorMessage ?? String.localized("Couldn't load this source"),
						rateLimited: outcome.rateLimited
					)
					if working[item.source] != nil {
						staleSourceIDs.insert(item.identifier)
					}
				}
			}

			// Publish progress (grows, never empties).
			self.sources = working
		}

		// A rate-limited source that still has a catalog keeps it, marked stale.
		for item in items where rateLimitedIDs.contains(item.identifier) && working[item.source] != nil {
			staleSourceIDs.insert(item.identifier)
		}

		if successes == items.count && rateLimitedIDs.isEmpty {
			lastLoadedAt = Date()
		} else {
			lastLoadedAt = nil
		}

		// Snapshot retention follows every configured source (including any
		// skipped by the transport policy or rate limit), not just the fetched
		// ones, so a skipped source keeps its last-known-good catalog.
		let allSourceIDs = Set(sourcesArray.map { Self._id(for: $0) })
		RepositorySnapshotCache.retainOnly(identifiers: allSourceIDs)
		Logger.misc.info("fetchSources DONE: \(working.count, privacy: .public)/\(items.count, privacy: .public) loaded")
	}
}
