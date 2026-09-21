//
//  InfoPlistEntitlementTests.swift
//  VexSignTests
//
//  Phase 1 Step 7 — Info.plist plan + entitlement builder characterization.
//
//  InfoPlistPlan is the single source of truth for what signing writes into an
//  app's Info.plist; MergedInfoPlist is what the editor UI shows. These tests
//  pin the current apply order (managed changes → managed removals → user
//  overrides → user removals) and the entitlement merge rules. JIT gating
//  itself is already covered by MissingFeatureTests; this file covers the
//  surrounding structure.
//

import XCTest
import Foundation
@testable import VexSign

final class InfoPlistEntitlementTests: XCTestCase {

	// MARK: - InfoPlistPlan.managedChanges

	func testManagedChangesCoverIdentityNameAndVersion() {
		var options = Options.defaultOptions
		options.appIdentifier = "com.vexsign.test.id"
		options.appName = "Display Name"
		options.appVersion = "2.5"

		let changes = InfoPlistPlan.managedChanges(for: options)
		XCTAssertEqual(changes["CFBundleIdentifier"] as? String, "com.vexsign.test.id")
		XCTAssertEqual(changes["CFBundleDisplayName"] as? String, "Display Name")
		XCTAssertEqual(changes["CFBundleName"] as? String, "Display Name")
		XCTAssertEqual(changes["CFBundleShortVersionString"] as? String, "2.5")
		XCTAssertEqual(changes["CFBundleVersion"] as? String, "2.5")
	}

	func testManagedChangesStayEmptyForDefaultOptions() {
		// Default options change nothing — a no-op sign keeps the bundle as-is.
		let changes = InfoPlistPlan.managedChanges(for: Options.defaultOptions)
		XCTAssertTrue(changes.isEmpty, "default options must not rewrite bundle keys: \(changes.keys)")
	}

	func testManagedChangesToggleKeys() {
		var options = Options.defaultOptions
		options.fileSharing = true
		options.itunesFileSharing = true
		options.proMotion = true
		options.gameMode = true
		options.ipadFullscreen = true
		options.appAppearance = .dark
		options.minimumAppRequirement = .v15

		let changes = InfoPlistPlan.managedChanges(for: options)
		XCTAssertEqual(changes["UISupportsDocumentBrowser"] as? Bool, true)
		XCTAssertEqual(changes["UIFileSharingEnabled"] as? Bool, true)
		XCTAssertEqual(changes["CADisableMinimumFrameDurationOnPhone"] as? Bool, true)
		XCTAssertEqual(changes["GCSupportsGameMode"] as? Bool, true)
		XCTAssertEqual(changes["UIRequiresFullScreen"] as? Bool, true)
		XCTAssertEqual(changes["UIUserInterfaceStyle"] as? String, "Dark")
		XCTAssertEqual(changes["MinimumOSVersion"] as? String, "15.0")
	}

	func testLiquidGlassExperimentsAreMutuallyExclusiveKeys() {
		var supporting = Options.defaultOptions
		supporting.experiment_supportLiquidGlass = true
		XCTAssertEqual(InfoPlistPlan.managedChanges(for: supporting)["UIDesignRequiresCompatibility"] as? Bool, false)

		var disabling = Options.defaultOptions
		disabling.experiment_disableLiquidGlass = true
		XCTAssertEqual(InfoPlistPlan.managedChanges(for: disabling)["UIDesignRequiresCompatibility"] as? Bool, true)
	}

	// MARK: - InfoPlistPlan.managedRemovals

	func testManagedRemovalsAlwaysStripDeviceAllowlist() {
		let removals = InfoPlistPlan.managedRemovals(for: Options.defaultOptions)
		XCTAssertEqual(removals, ["UISupportedDevices"])
	}

	func testManagedRemovalsAreConditionalForSchemesAndMinimumOS() {
		var options = Options.defaultOptions
		options.removeURLScheme = true
		options.removeMinimumOSVersion = true

		let removals = InfoPlistPlan.managedRemovals(for: options)
		XCTAssertTrue(removals.contains("CFBundleURLTypes"))
		XCTAssertTrue(removals.contains("MinimumOSVersion"))
		XCTAssertTrue(removals.contains("UISupportedDevices"))
	}

	// MARK: - InfoPlistPlan.apply (ordering contract)

	func testApplyWritesManagedThenRemovalsThenUserOverridesWin() {
		var options = Options.defaultOptions
		options.appIdentifier = "com.managed.id"
		options.appName = "Managed Name"
		options.removeURLScheme = true
		// The user overrides the managed identifier AND removes the managed name.
		options.infoPlistOverrideDict = ["CFBundleIdentifier": "com.user.id"]
		options.infoPlistRemovals = ["CFBundleDisplayName"]

		let dictionary = NSMutableDictionary(dictionary: [
			"CFBundleIdentifier": "com.original.id",
			"CFBundleDisplayName": "Original Name",
			"CFBundleURLTypes": [["CFBundleURLSchemes": ["orig"]]],
			"UntouchedKey": "kept",
		])

		InfoPlistPlan.apply(options, to: dictionary)

		XCTAssertEqual(dictionary["CFBundleIdentifier"] as? String, "com.user.id", "user overrides beat managed changes")
		XCTAssertNil(dictionary["CFBundleDisplayName"], "user removals beat managed changes")
		XCTAssertEqual(dictionary["CFBundleName"] as? String, "Managed Name", "only the display name was removed by the user")
		XCTAssertNil(dictionary["CFBundleURLTypes"], "managed removal of URL schemes applies")
		XCTAssertEqual(dictionary["UntouchedKey"] as? String, "kept")
	}

	func testApplyWithDefaultOptionsOnlyStripsDeviceAllowlist() {
		let dictionary = NSMutableDictionary(dictionary: [
			"CFBundleIdentifier": "com.original.id",
			"UISupportedDevices": ["iPhone14,2"],
		])
		InfoPlistPlan.apply(Options.defaultOptions, to: dictionary)

		XCTAssertEqual(dictionary["CFBundleIdentifier"] as? String, "com.original.id")
		XCTAssertNil(dictionary["UISupportedDevices"])
	}

	// MARK: - MergedInfoPlist (editor view)

	private func sampleOriginal() -> [String: Any] {
		[
			"CFBundleIdentifier": "com.original.id",
			"CFBundleDisplayName": "Original",
			"UIBackgroundModes": ["audio"],
			"UISupportedDevices": ["iPhone14,2"],
		]
	}

	func testMergedInfoPlistStatusClassification() {
		var options = Options.defaultOptions
		options.appIdentifier = "com.managed.id"                    // managed change
		options.infoPlistOverrideDict = ["CFBundleDisplayName": "User"] // user override
		options.infoPlistRemovals = ["UIBackgroundModes"]           // user removal

		let merged = MergedInfoPlist(original: sampleOriginal(), options: options)

		XCTAssertEqual(merged.status(for: "CFBundleIdentifier"), .managed)
		XCTAssertEqual(merged.status(for: "CFBundleDisplayName"), .overridden)
		XCTAssertEqual(merged.status(for: "UIBackgroundModes"), .removed)
		XCTAssertEqual(merged.status(for: "UISupportedDevices"), .removed, "managed removals classify as removed")
	}

	func testMergedInfoPlistEffectiveReflectsFullPipeline() {
		var options = Options.defaultOptions
		options.appIdentifier = "com.managed.id"
		options.infoPlistOverrideDict = ["Extra": "value"]

		let merged = MergedInfoPlist(original: sampleOriginal(), options: options)
		let effective = merged.effective

		XCTAssertEqual(effective["CFBundleIdentifier"] as? String, "com.managed.id")
		XCTAssertEqual(effective["Extra"] as? String, "value")
		XCTAssertNil(effective["UISupportedDevices"])
		XCTAssertEqual(effective["CFBundleDisplayName"] as? String, "Original")
	}

	func testMergedInfoPlistBackgroundModesRespectRemoval() {
		var options = Options.defaultOptions
		options.infoPlistRemovals = ["UIBackgroundModes"]
		var merged = MergedInfoPlist(original: sampleOriginal(), options: options)
		XCTAssertEqual(merged.backgroundModes, [], "a removed key must report no background modes")

		options.infoPlistRemovals = []
		merged = MergedInfoPlist(original: sampleOriginal(), options: options)
		XCTAssertEqual(merged.backgroundModes, ["audio"])
	}

	func testInfoPlistChangeCountTracksOverridesAndRemovals() {
		var options = Options.defaultOptions
		XCTAssertEqual(options.infoPlistChangeCount, 0)

		options.infoPlistOverrideDict = ["A": "1", "B": "2"]
		options.infoPlistRemovals = ["C"]
		XCTAssertEqual(options.infoPlistChangeCount, 3)

		// Round-trip: values survive the plist blob encoding.
		XCTAssertEqual(options.infoPlistOverrideDict["A"] as? String, "1")
	}

	// MARK: - EntitlementBuilder merge rules

	func testEntitlementBuilderPreservesBaseWhenJITIsOffOrUnsupported() {
		let base: [String: Any] = ["application-identifier": "TEAM.com.app"]

		let off = EntitlementBuilder.entitlements(base: base, enableJIT: false, supportsJIT: true)
		XCTAssertEqual(off as NSDictionary, base as NSDictionary)

		let unsupported = EntitlementBuilder.entitlements(base: base, enableJIT: true, supportsJIT: false)
		XCTAssertEqual(unsupported as NSDictionary, base as NSDictionary, "PPQLess certificates must never gain JIT keys")
	}

	func testEntitlementBuilderAddsAllJITKeysWhenAllowed() {
		let built = EntitlementBuilder.entitlements(base: [:], enableJIT: true, supportsJIT: true)
		for key in EntitlementBuilder.jitEntitlementKeys {
			XCTAssertEqual(built[key] as? Bool, true, "\(key) must be granted")
		}
	}

	func testAddsJITDetectsAlreadyGrantedKeys() {
		let alreadyGranted: [String: Any] = [
			"dynamic-codesigning": true,
			"com.apple.security.cs.allow-jit": true,
			"com.apple.security.cs.allow-unsigned-executable-memory": true,
		]
		XCTAssertFalse(
			EntitlementBuilder.addsJIT(base: alreadyGranted, enableJIT: true, supportsJIT: true),
			"nothing to add when every key is already true"
		)
		XCTAssertTrue(EntitlementBuilder.addsJIT(base: ["dynamic-codesigning": true], enableJIT: true, supportsJIT: true))
		XCTAssertFalse(EntitlementBuilder.addsJIT(base: [:], enableJIT: false, supportsJIT: true))
	}

	func testEntitlementBuilderWritesPlistZsignCanRead() throws {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("vexsign-entitlements-\(UUID().uuidString).plist")
		addTeardownBlock { try? FileManager.default.removeItem(at: url) }

		let written = try EntitlementBuilder.write(
			EntitlementBuilder.entitlements(base: ["get-task-allow": true], enableJIT: true, supportsJIT: true),
			to: url
		)
		XCTAssertEqual(written, url)

		let parsed = try XCTUnwrap(NSDictionary(contentsOf: url))
		XCTAssertEqual(parsed["get-task-allow"] as? Bool, true)
		XCTAssertEqual(parsed["dynamic-codesigning"] as? Bool, true)
	}
}
