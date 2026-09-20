//
//  AdvancedSigningSettingsView.swift
//  VexSign — FlareStore / FeatherPlus / MySign Advanced Signing & Patches
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct AdvancedSigningSettingsView: View {
    @AppStorage("VexSign.signing.buildSDKSpoof") private var buildSDKSpoof = false
    @AppStorage("VexSign.signing.targetSDKVersion") private var targetSDKVersion = "iOS 26.0"
    @AppStorage("VexSign.signing.clearCompatOptOut") private var clearCompatOptOut = true
    @AppStorage("VexSign.signing.forceFileSharing") private var forceFileSharing = false
    @AppStorage("VexSign.signing.removeMinOSVersion") private var removeMinOSVersion = true
    @AppStorage("VexSign.signing.machoSliceThinning") private var machoSliceThinning = true
    @AppStorage("VexSign.signing.randomizeBundleId") private var randomizeBundleId = false
    @AppStorage("VexSign.signing.stripURLSchemes") private var stripURLSchemes = false

    private let sdkOptions = ["iOS 17.0", "iOS 18.0", "iOS 26.0", "iOS 27.0"]

    var body: some View {
        NBList(.localized("Advanced Signing & Patches")) {
            headerSection

            flareStoreSDKSection

            compatibilitySection

            machoAndPackagingSection
        }
    }

    private var headerSection: some View {
        NBSection(.localized("Advanced Signer Engine")) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(.localized("Binary & SDK Patching"))
                        .font(.headline)
                    Text(.localized("Features curated from FlareStore, FeatherPlus and MySign."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var flareStoreSDKSection: some View {
        NBSection(.localized("Build SDK Spoofing")) {
            Toggle(.localized("Spoof Build SDK Version"), isOn: $buildSDKSpoof)
                .tint(Color.orange)

            if buildSDKSpoof {
                Picker(.localized("Target SDK"), selection: $targetSDKVersion) {
                    ForEach(sdkOptions, id: \.self) { sdk in
                        Text(sdk).tag(sdk)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle(.localized("Clear Compatibility Opt-Out"), isOn: $clearCompatOptOut)
                .tint(Color.orange)
        } footer: {
            Text(.localized("Ported from FlareStore 1.3. Forces an app to build against modern iOS SDKs and clears the compatibility opt-out flag so redesigned iOS 26+ UI paradigms render natively."))
        }
    }

    private var compatibilitySection: some View {
        NBSection(.localized("Info.plist Patches")) {
            Toggle(.localized("Force Files App Sharing"), isOn: $forceFileSharing)
                .tint(Color.userTint)

            Toggle(.localized("Remove Minimum iOS Version"), isOn: $removeMinOSVersion)
                .tint(Color.userTint)

            Toggle(.localized("Strip Existing URL Schemes"), isOn: $stripURLSchemes)
                .tint(Color.userTint)

            Toggle(.localized("Randomize Bundle ID (Duplicate App)"), isOn: $randomizeBundleId)
                .tint(Color.userTint)
        } footer: {
            Text(.localized("Enables UIFileSharingEnabled to expose app documents directly in the Files app. Removes MinimumOSVersion to allow running legacy or newer apps on incompatible firmware."))
        }
    }

    private var machoAndPackagingSection: some View {
        NBSection(.localized("Mach-O & Binary Optimization")) {
            Toggle(.localized("Mach-O Architecture Thinning"), isOn: $machoSliceThinning)
                .tint(Color.userTint)
        } footer: {
            Text(.localized("Ported from MySign and Feather. Strips unnecessary 32-bit and extra architecture slices from Mach-O binaries to reduce final signed IPA size by up to 40%."))
        }
    }
}
