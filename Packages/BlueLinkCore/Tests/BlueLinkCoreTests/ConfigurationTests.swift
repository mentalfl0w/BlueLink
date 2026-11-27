import XCTest
@testable import BlueLinkCore

final class ConfigurationTests: XCTestCase {
    func testRoundTripPreservesPauseAndPolicies() throws {
        var policy = DevicePolicy()
        policy.connectOnDisplayWake = false
        policy.preferredAudioUID = "BuiltInSpeakerDevice"
        let device = TestFixtures.managed(policy: policy, paused: true)
        let config = TestFixtures.configuration([device], enabled: false)

        let data = try ConfigurationCoder.encode(config)
        guard case .loaded(let decoded) = ConfigurationCoder.decode(data) else {
            return XCTFail("expected loaded configuration")
        }
        XCTAssertEqual(decoded, config)
        XCTAssertTrue(decoded.devices[0].isPaused)
        XCTAssertEqual(decoded.devices[0].policy.preferredAudioUID, "BuiltInSpeakerDevice")
    }

    func testUnknownVersionIsRejectedWithoutRewriting() {
        let json = #"{"schemaVersion": 99, "isGloballyEnabled": true, "devices": []}"#
        XCTAssertEqual(ConfigurationCoder.decode(Data(json.utf8)), .unsupportedVersion(99))
    }

    func testMissingVersionIsReportedAsUnsupported() {
        let json = #"{"isGloballyEnabled": true, "devices": []}"#
        XCTAssertEqual(ConfigurationCoder.decode(Data(json.utf8)), .unsupportedVersion(0))
    }

    func testCorruptPayloadIsReported() {
        guard case .corrupt = ConfigurationCoder.decode(Data("not json".utf8)) else {
            return XCTFail("expected corrupt result")
        }
        guard case .corrupt = ConfigurationCoder.decode(Data(#"{"schemaVersion": 1, "devices": 5}"#.utf8)) else {
            return XCTFail("expected corrupt result for wrong field type")
        }
    }

    func testSanitizeDeduplicatesAndTrimsNames() {
        let duplicate = TestFixtures.managed(TestFixtures.deviceB, name: "  Second  ")
        var config = TestFixtures.configuration([
            TestFixtures.managed(name: "   "),
            duplicate,
            duplicate
        ])
        config.devices[0].policy.preferredAudioUID = "   "

        let sanitized = ConfigurationCoder.sanitize(config)
        XCTAssertEqual(sanitized.devices.count, 2)
        XCTAssertEqual(sanitized.devices[0].cachedName, TestFixtures.deviceA.address)
        XCTAssertEqual(sanitized.devices[1].cachedName, "Second")
        XCTAssertNil(sanitized.devices[0].policy.preferredAudioUID)
    }

    func testDeviceIDNormalizationRejectsInvalidAddresses() {
        XCTAssertEqual(DeviceID(raw: "aa:bb:cc:dd:ee:ff")?.address, "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(DeviceID(raw: "aabbccddeeff")?.address, "AA-BB-CC-DD-EE-FF")
        XCTAssertNil(DeviceID(raw: "AA-BB-CC"))
        XCTAssertNil(DeviceID(raw: "ZZ-88-11-22-33-44"))
    }
}
