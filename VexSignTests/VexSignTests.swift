//
//  VexSignTests.swift
//  VexSignTests
//
//  Created by Lakhan Lothiyi on 19/04/2025.
//

import XCTest
import AltSourceKit
@testable import VexSign

final class VexSignTests: XCTestCase {

	/// Fetches every default repo and decodes it with a plain `JSONDecoder`,
	/// mirroring the production path (`NBFetchService`): `ASRepository` handles
	/// its own date parsing via `DateParsed`, so no decoding strategy is needed.
	///
	/// This test needs live network access, so it only runs when the CI gate
	/// (or a developer) opts in via `VEXSIGN_INTEGRATION_TESTS=1` — the PR
	/// suite must stay deterministic. The decode contract itself is covered
	/// offline by `testRepoPayloadDecodesFromFixture` below.
	func testRepoParsing() async throws {
		try IntegrationGate.skipUnlessEnabled()
		let repoDatas: [URL: Data] = try await withThrowingTaskGroup(of: (URL, Data).self, returning: [URL: Data].self) { group in
			for url in repoURLs {
				group.addTask {
					let (data, _) = try await URLSession.shared.data(from: url)
					return (url, data)
				}
			}

			var results: [URL: Data] = [:]
			for try await result in group {
				results[result.0] = result.1
			}

			return results
		}

		let decoder = JSONDecoder()

		XCTAssertFalse(repoDatas.isEmpty, "No repo data was fetched")

		for (url, data) in repoDatas {
			do {
				let repo = try decoder.decode(ASRepository.self, from: data)
				XCTAssertFalse(repo.apps.isEmpty, "Repository decoded but contains no apps: \(url)")
			} catch {
				XCTFail("Failed to decode repo data: \(error)\n\nFailed for \(url)")
			}
		}
	}

	/// Offline counterpart of `testRepoParsing`: the committed sample repo
	/// fixture must decode through the same `ASRepository` path with the same
	/// plain `JSONDecoder` the production fetcher uses.
	func testRepoPayloadDecodesFromFixture() throws {
		let url = TestFixtures.url("Sources/sample-repo.json")
		let data = try Data(contentsOf: url)
		let repo = try JSONDecoder().decode(ASRepository.self, from: data)

		XCTAssertEqual(repo.name, "VexSign")
		XCTAssertFalse(repo.apps.isEmpty)
		XCTAssertFalse(repo.apps[0].versions.isEmpty)
	}

	/// Repositories can be pasted as obfuscated "codes" in two known formats.
	/// `ASDeobfuscator` (via `ASDecrypt` for the Esign envelope) handles both —
	/// this is the same entry point `SourcesAddView+Repositories` calls.
	func testRepoDeobfuscation() {
		// Plain base64 export (KravaSign/MapleSign): newline- or `[K$]`/`[M$]`-separated.
		let kravaURLs = ASDeobfuscator(with: obfuscatedKUrl).decode()
		XCTAssertEqual(kravaURLs, ["https://cdn.altstore.io/file/altstore/apps.json"])

		// Esign envelope `source[...]`: base64 payload XOR'd with the bundled key.
		let esign = ASDecrypt(input: obfEUrl)
		XCTAssertNotNil(esign.extractBase64(), "source[...] envelope failed to extract its base64 payload")

		// The static entry point must route each format the same way.
		XCTAssertEqual(ASDeobfuscator.decode(with: obfuscatedKUrl), kravaURLs)
		// Malformed envelopes must degrade to [] instead of crashing.
		XCTAssertEqual(ASDeobfuscator.decode(with: "source[!!!not-base64!!!]"), [])
		XCTAssertEqual(ASDeobfuscator.decode(with: ""), [])
	}
}

let obfuscatedKUrl = "aHR0cHM6Ly9jZG4uYWx0c3RvcmUuaW8vZmlsZS9hbHRzdG9yZS9hcHBzLmpzb24="
let obfEUrl = "source[5GHxhb1U7Lc5jIMpumASbN2teg9dyK5EAazzwnfm1/gPKQPTWzcz/Gq3Njt97KapLNMztZCR3sHbMw/AMSpBsztQijHaOP/HgNtFseMyB1U=]"

let repoURLs: [URL] = [
	"https://cdn.altstore.io/file/altstore/apps.json",
].compactMap { URL(string: $0) }
