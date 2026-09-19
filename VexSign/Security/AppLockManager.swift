//
//  AppLockManager.swift
//  VexSign
//
//  Optional Face ID / Touch ID / passcode gate. The app locks whenever it leaves
//  the foreground (and on cold start while enabled) and unlocks through
//  LocalAuthentication, which falls back to the device passcode automatically.
//
//  If the device has no passcode at all, evaluation is impossible — the manager
//  turns itself off rather than trapping the user behind an unpickable lock.
//

import Foundation
import LocalAuthentication

@MainActor
final class AppLockManager: ObservableObject {
	static let shared = AppLockManager()

	static let enabledKey = "VexSign.security.appLockEnabled"

	/// True while the lock overlay should cover the UI.
	@Published private(set) var isLocked: Bool
	@Published private(set) var isAuthenticating = false
	@Published private(set) var lastMessage: String?

	private init() {
		// Cold starts begin locked too, not just backgrounded ones.
		isLocked = Self.isEnabled
	}

	static var isEnabled: Bool {
		UserDefaults.standard.bool(forKey: enabledKey)
	}

	/// "Face ID" / "Touch ID" for labels, or nil when only the passcode is available.
	static var biometryName: String? {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return nil }
		switch context.biometryType {
		case .faceID: return String.localized("Face ID")
		case .touchID: return String.localized("Touch ID")
		default: return nil
		}
	}

	/// Locks when the app goes to the background (no-op while already locked).
	func lockIfNeeded() {
		guard Self.isEnabled, !isLocked, !isAuthenticating else { return }
		isLocked = true
	}

	/// Prompts for unlock when the app becomes active while locked.
	func authenticateIfNeeded() {
		guard Self.isEnabled, isLocked else { return }
		authenticate()
	}

	func authenticate() {
		guard !isAuthenticating else { return }

		let context = LAContext()
		context.localizedCancelTitle = String.localized("Cancel")

		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
			// No device passcode — keeping the lock on would brick the app, so disable it.
			UserDefaults.standard.set(false, forKey: Self.enabledKey)
			lastMessage = error?.localizedDescription ?? String.localized("No device passcode is set, so App Lock cannot run.")
			isLocked = false
			return
		}

		isAuthenticating = true
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String.localized("Unlock VexSign")) { [weak self] success, authError in
			DispatchQueue.main.async {
				guard let self else { return }
				self.isAuthenticating = false
				if success {
					self.isLocked = false
					self.lastMessage = nil
				} else {
					self.lastMessage = authError?.localizedDescription
				}
			}
		}
	}
}
