import XCTest
@testable import VexSign

final class EcosystemTests: XCTestCase {
    private func sample() -> RepositoryDocument {
        var app = RepositoryApp()
        app.name = "Example"; app.bundleIdentifier = "com.example.app"
        app.versionDate = "2026-09-19T00:00:00Z"
        app.downloadURL = "https://example.com/app.ipa?a=1&b=2"
        app.iconURL = "https://example.com/icon.png"; app.size = 1024
        return RepositoryDocument(name: "Examples", identifier: "com.example.source", apps: [app])
    }

    func testCommonFormatsRoundTrip() throws {
        for format in RepositoryFormat.allCases {
            let original = sample()
            let files = try RepositoryExporter.encode(original, as: format)
            let decoded = try RepositoryImporter.decode(files.source, format: format)
            XCTAssertEqual(decoded.name, original.name)
            XCTAssertEqual(decoded.apps.first?.bundleIdentifier, original.apps.first?.bundleIdentifier)
            XCTAssertEqual(decoded.apps.first?.downloadURL, original.apps.first?.downloadURL)
            let split = try RepositoryImporter.decode(files.source, format: format, appsData: files.apps)
            XCTAssertEqual(split.apps.count, 1)
        }
    }
    func testUnknownProviderMetadataSurvivesAltStoreRoundTrip() throws {
        var doc = sample()
        doc.extra["userInfo"] = .object(["key": .string("value")])
        doc.apps[0].extra["appPermissions"] = .object(["entitlements": .array([])])
        let decoded = try RepositoryImporter.decode(RepositoryExporter.encode(doc, as: .altStore).source)
        XCTAssertEqual(decoded.extra["userInfo"], doc.extra["userInfo"])
        XCTAssertEqual(decoded.apps[0].extra["appPermissions"], doc.apps[0].extra["appPermissions"])
    }
    func testMalformedAndOversizedInputsAreRejected() {
        XCTAssertThrowsError(try RepositoryImporter.decode(Data("{".utf8)))
        XCTAssertThrowsError(try RepositoryImporter.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try RepositoryImporter.decode(Data(repeating: 0, count: RepositoryImporter.maximumBytes + 1)))
    }
    func testDuplicatesInvalidURLsAndSafeFixes() {
        var doc = sample()
        doc.apps.append(doc.apps[0])
        doc.apps[1].id = UUID()
        XCTAssertTrue(RepositoryValidator.validate(doc).contains { $0.message.contains("Duplicate bundle") })
        doc.apps.removeLast()
        doc.apps[0].downloadURL = " https://example.com/app.ipa "
        doc.apps[0].screenshotURLs = ["https://example.com/1.png", "https://example.com/1.png"]
        XCTAssertTrue(RepositoryValidator.validate(doc).contains { $0.fix != nil })
        RepositoryValidator.applySafeFixes(to: &doc)
        XCTAssertEqual(doc.apps[0].screenshotURLs.count, 1)
        XCTAssertFalse(RepositoryValidator.validate(doc).contains { $0.severity == .error })
        XCTAssertNil(RepositoryValidator.webURL("file:///private/key.p12"))
        XCTAssertNil(RepositoryValidator.webURL("https://user:password@example.com"))
        XCTAssertNil(RepositoryValidator.webURL("javascript:alert(1)"))
    }
    func testCloneIDsAvoidExistingIDsAndValidateBounds() throws {
        let plans = try ClonePlan.make(bundleID: "com.example.app", name: "Example", count: 2, existing: ["com.example.app.clone1"])
        XCTAssertEqual(plans.map(\.bundleIdentifier), ["com.example.app.clone2", "com.example.app.clone3"])
        XCTAssertThrowsError(try ClonePlan.make(bundleID: "../evil", name: "Example", count: 1, existing: []))
        XCTAssertThrowsError(try ClonePlan.make(bundleID: "com.example.app", name: "Example", count: 21, existing: []))
    }
    func testManifestSerializationAndInstallLinkEncoding() throws {
        let download = try XCTUnwrap(URL(string: "https://example.com/a.ipa?x=1&y=2"))
        let data = try OTAExporter.manifest(.init(name: "A & B", bundleIdentifier: "com.example.app", version: "1.0", downloadURL: download, iconURL: nil))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertNotNil(object?["items"])
        let url = try XCTUnwrap(URL(string: "https://example.com/manifest?token=a&x=b"))
        let link = try OTAExporter.installLink(manifestURL: url)
        XCTAssertEqual(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value, url.absoluteString)
        XCTAssertThrowsError(try OTAExporter.installLink(manifestURL: XCTUnwrap(URL(string: "http://example.com/a"))))
    }
    func testUnsignedOrUnknownIsNotGoodCertificateEvidence() {
        XCTAssertEqual(CertificateStatusValue(apiStatus: "unsigned"), .unknown)
        XCTAssertEqual(CertificateStatusValue(apiStatus: "revoked"), .revoked)
        XCTAssertEqual(CertificateStatusValue(apiStatus: "signed"), .signed)
    }
    func testRankingUsesFavoritesWithoutFabricatedGlobalDownloads() {
        let app = DiscoveryApp(id: "a", source: "s", bundleIdentifier: "com.example.app", name: "Example", summary: "", developer: "", category: "", version: "1", icon: nil, download: nil, updated: Date(), releases: 1)
        let now = Date()
        var signals = DiscoverySignals()
        let original = DiscoveryRanking.score(app, signals: signals, now: now)
        signals.favorites.insert(app.id)
        XCTAssertEqual(DiscoveryRanking.score(app, signals: signals, now: now), original + 4, accuracy: 0.00001)
    }
}
