//
//  SourcePreferences.swift
//  VexSign
//
//  Local repository ordering, trust, visibility, and refresh metadata.
//  Trust is deliberately user-assigned: a green badge never claims that VexSign
//  cryptographically verified a repository publisher.
//

import Foundation

enum SourcePreferences {
	private static let pinnedKey = "VexSign.sources.pinned"
	private static let priorityKey = "VexSign.sources.priority"
	private static let trustedKey = "VexSign.sources.trusted"
	private static let lastFetchKey = "VexSign.sources.lastFetch"
	private static let lastErrorKey = "VexSign.sources.lastError"
	private static let hideDuplicatesKey = "VexSign.sources.hideDuplicates"

	static var hideDuplicates: Bool {
		get { UserDefaults.standard.bool(forKey: hideDuplicatesKey) }
		set { UserDefaults.standard.set(newValue, forKey: hideDuplicatesKey) }
	}

	static func isPinned(_ id: String) -> Bool {
		pinned.contains(id)
	}

	static func setPinned(_ id: String, pinned isPinned: Bool) {
		var set = pinned
		if isPinned { set.insert(id) } else { set.remove(id) }
		UserDefaults.standard.set(Array(set), forKey: pinnedKey)
	}

	// MARK: - Repository priority

	/// Lower values win when two repositories publish the same bundle identifier.
	/// The dictionary is intentionally sparse so adding a repository never rewrites
	/// an existing user's choices.
	static func priority(for id: String) -> Int {
		(UserDefaults.standard.dictionary(forKey: priorityKey) as? [String: Int])?[id] ?? Int.max
	}

	static func orderedIDs(for ids: [String]) -> [String] {
		order(for: ids)
	}

	static func setOrder(_ ids: [String]) {
		var priorities: [String: Int] = [:]
		for (index, id) in ids.enumerated() { priorities[id] = index }
		UserDefaults.standard.set(priorities, forKey: priorityKey)
		// Keep the array as the human-readable, migration-friendly representation.
		UserDefaults.standard.set(ids, forKey: priorityKey + ".order")
	}

	/// Returns a stable source order while retaining the old dictionary format if
	/// an older build saved one. New builds use the explicit order array.
	static func order(for ids: [String]) -> [String] {
		let available = Set(ids)
		let stored = UserDefaults.standard.stringArray(forKey: priorityKey + ".order") ?? []
		if !stored.isEmpty {
			let known = stored.filter { available.contains($0) }
			let missing = ids.filter { !known.contains($0) }.sorted()
			return known + missing
		}
		// Migrate the first implementation, which stored only a priority map.
		if let legacy = UserDefaults.standard.dictionary(forKey: priorityKey) as? [String: Int], !legacy.isEmpty {
			return ids.sorted {
				let lhs = legacy[$0] ?? Int.max
				let rhs = legacy[$1] ?? Int.max
				if lhs != rhs { return lhs < rhs }
				return $0 < $1
			}
		}
		return ids.sorted()
	}

	// MARK: - User trust marker

	static func isTrusted(_ id: String) -> Bool {
		Set(UserDefaults.standard.stringArray(forKey: trustedKey) ?? []).contains(id)
	}

	static func setTrusted(_ id: String, trusted: Bool) {
		var values = Set(UserDefaults.standard.stringArray(forKey: trustedKey) ?? [])
		if trusted { values.insert(id) } else { values.remove(id) }
		UserDefaults.standard.set(Array(values).sorted(), forKey: trustedKey)
	}

	static func lastFetch(for id: String) -> Date? {
		guard let map = UserDefaults.standard.dictionary(forKey: lastFetchKey) as? [String: Double] else { return nil }
		guard let value = map[id] else { return nil }
		return Date(timeIntervalSince1970: value)
	}

	static func lastError(for id: String) -> String? {
		(UserDefaults.standard.dictionary(forKey: lastErrorKey) as? [String: String])?[id]
	}

	static func recordFetch(id: String, error: String?) {
		var fetches = UserDefaults.standard.dictionary(forKey: lastFetchKey) as? [String: Double] ?? [:]
		fetches[id] = Date().timeIntervalSince1970
		UserDefaults.standard.set(fetches, forKey: lastFetchKey)

		var errors = UserDefaults.standard.dictionary(forKey: lastErrorKey) as? [String: String] ?? [:]
		if let error, !error.isEmpty {
			errors[id] = error
		} else {
			errors.removeValue(forKey: id)
		}
		UserDefaults.standard.set(errors, forKey: lastErrorKey)
	}

	private static var pinned: Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
	}
}
