import XCTest
@testable import PhrasePerch

final class ConfigurationFormatTests: XCTestCase {
    func testLegacyExpansionFieldIsIgnoredAndOmittedOnSave() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let preferences = Preferences()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(preferences)) as? [String: Any])
        XCTAssertNil(object["menuExpansionMode"])
        for legacy: Any in ["fixedCenter", "navigationNode", "unknown", NSNull(), 1] {
            object["menuExpansionMode"] = legacy
            let restored = try decoder.decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored, preferences)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(restored)) as? [String: Any])
            XCTAssertNil(saved["menuExpansionMode"])
        }
        object.removeValue(forKey: "menuAnchorMode")
        XCTAssertThrowsError(try decoder.decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testCurrentFormatRoundTripAndRejectsOtherVersions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = AppProfile(application: ApplicationIdentity(bundleIdentifier: "test", fallbackBundlePath: nil),
            displayName: "测试", displayMode: .both, buttons: [Snippet(title: "原文", text: "正文 👩‍💻\n")])
        let config = AppConfiguration(profiles: [profile])
        let disk = JSONConfigurationStorage(directory: directory)
        try await disk.save(config)
        let restored = try await disk.load()
        XCTAssertEqual(restored, config)
        for version in [0, 2, 3, 4, 999] {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
            object["schemaVersion"] = version
            do { _ = try await disk.decode(JSONSerialization.data(withJSONObject: object)); XCTFail("Unsupported version") } catch {}
        }
        var incomplete = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        var profiles = incomplete["profiles"] as! [[String: Any]]
        profiles[0].removeValue(forKey: "rootNodes"); incomplete["profiles"] = profiles
        do { _ = try await disk.decode(JSONSerialization.data(withJSONObject: incomplete)); XCTFail("Missing root nodes") } catch {}
        let unchanged = try await disk.load()
        XCTAssertEqual(unchanged, config)
    }
    @MainActor
    func testFreshProfilesAreEmptyAndOnlyCreatedOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = ApplicationCatalog.initialConfiguration()
        XCTAssertEqual(initial.profiles.map(\.displayName), ["Safari", "ChatGPT"])
        XCTAssertTrue(initial.profiles.allSatisfy { $0.buttons.isEmpty && $0.groups.isEmpty && $0.rootNodes.isEmpty })
        let disk = JSONConfigurationStorage(directory: directory, initialConfiguration: initial)
        let fresh = try await disk.load()
        XCTAssertEqual(fresh, initial)
        try await disk.save(AppConfiguration())
        let empty = try await disk.load()
        XCTAssertTrue(empty.profiles.isEmpty)
    }
}
