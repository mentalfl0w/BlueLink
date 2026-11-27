import XCTest
import BlueLinkCore
@testable import MacIntegration

final class DisplayAggregationTests: XCTestCase {
    func testAllDisplaysAsleepIsAsleep() {
        XCTAssertEqual(DisplayAggregation.state(onlineDisplayCount: 2, asleepDisplayCount: 2), .asleep)
    }

    func testOneAwakeDisplayKeepsAwake() {
        XCTAssertEqual(DisplayAggregation.state(onlineDisplayCount: 3, asleepDisplayCount: 1), .awake)
    }

    func testNoOnlineDisplayIsUnknown() {
        XCTAssertEqual(DisplayAggregation.state(onlineDisplayCount: 0, asleepDisplayCount: 0), .unknown)
    }
}

final class BluetoothClassifierTests: XCTestCase {
    func testRealInputDevicesAreDetected() {
        // Magic Trackpad and Magic Keyboard from the verification host.
        XCTAssertTrue(BluetoothDeviceClassifier.isInputDevice(classOfDevice: 0x002594))
        XCTAssertTrue(BluetoothDeviceClassifier.isInputDevice(classOfDevice: 0x002540))
        XCTAssertFalse(BluetoothDeviceClassifier.isAudioDevice(classOfDevice: 0x002594))
    }

    func testAudioDevicesAreDetected() {
        // Redmi speaker and AirPods.
        XCTAssertTrue(BluetoothDeviceClassifier.isAudioDevice(classOfDevice: 0x240404))
        XCTAssertTrue(BluetoothDeviceClassifier.isAudioDevice(classOfDevice: 0x240418))
        XCTAssertFalse(BluetoothDeviceClassifier.isInputDevice(classOfDevice: 0x240404))
    }

    func testUnknownClassIsNeither() {
        XCTAssertFalse(BluetoothDeviceClassifier.isInputDevice(classOfDevice: 0))
        XCTAssertFalse(BluetoothDeviceClassifier.isAudioDevice(classOfDevice: 0))
    }
}

final class IOBluetoothTransportTests: XCTestCase {
    func testPageTimeoutConversionAndClamping() {
        XCTAssertEqual(IOBluetoothTransport.pageTimeout(for: .seconds(5)), 8_000)
        XCTAssertEqual(IOBluetoothTransport.pageTimeout(for: .milliseconds(1)), 0x0016)
        XCTAssertEqual(IOBluetoothTransport.pageTimeout(for: .seconds(100)), 0xFFFF)
    }

    func testPairedDeviceListingDoesNotCrash() async throws {
        let transport = IOBluetoothTransport()
        let devices = try await transport.pairedDevices()
        for device in devices {
            XCTAssertEqual(device.id.address.count, 17)
        }
    }
}

final class SanitizerTests: XCTestCase {
    func testBluetoothAddressesAreRemoved() {
        let message = "connected AA-BB-CC-DD-EE-FF and 11:22:33:44:55:66"
        let sanitized = Sanitizer.sanitize(message)
        XCTAssertFalse(sanitized.contains("AA-BB-CC"))
        XCTAssertFalse(sanitized.contains("11:22"))
        XCTAssertTrue(sanitized.contains("<bluetooth-address>"))
    }

    func testHomePathIsRedacted() {
        let sanitized = Sanitizer.sanitize("/Users/someone/Library/Application Support/BlueLink/config.json")
        XCTAssertFalse(sanitized.contains("someone"))
        XCTAssertTrue(sanitized.hasPrefix("~/"))
    }

    func testNewlinesAreFoldedAndLengthBounded() {
        let sanitized = Sanitizer.sanitize(String(repeating: "a\n", count: 500))
        XCTAssertFalse(sanitized.contains("\n"))
        XCTAssertLessThanOrEqual(sanitized.count, 600)
    }
}

final class UpdateCheckerTests: XCTestCase {
    private let payload = """
    [
      {"tag_name":"v1.2.0","name":"1.2.0","body":"notes","html_url":"https://example.com/1.2.0","draft":false,"prerelease":false},
      {"tag_name":"v1.3.0","name":"1.3.0","body":"newer","html_url":"https://example.com/1.3.0","draft":false,"prerelease":false},
      {"tag_name":"v2.0.0","name":"beta","body":"","html_url":"https://example.com/2.0.0","draft":false,"prerelease":true},
      {"tag_name":"v9.0.0","name":"draft","body":"","html_url":"https://example.com/9.0.0","draft":true,"prerelease":false}
    ]
    """.data(using: .utf8)!

    func testNewestStableReleaseWins() {
        let release = UpdateChecker.newestRelease(from: payload, currentVersion: "1.2.1")
        XCTAssertEqual(release?.version, "1.3.0")
        XCTAssertEqual(release?.pageURL.absoluteString, "https://example.com/1.3.0")
    }

    func testUpToDateReturnsNil() {
        XCTAssertNil(UpdateChecker.newestRelease(from: payload, currentVersion: "1.3.0"))
        XCTAssertNil(UpdateChecker.newestRelease(from: payload, currentVersion: "1.4"))
    }

    func testInvalidPayloadReturnsNil() {
        XCTAssertNil(UpdateChecker.newestRelease(from: Data("{}".utf8), currentVersion: "1.0"))
    }

    func testVersionComparison() {
        XCTAssertLessThan(VersionNumber("1.2.9"), VersionNumber("1.2.10"))
        XCTAssertEqual(VersionNumber("v1.2"), VersionNumber("1.2.0"))
        XCTAssertLessThan(VersionNumber("1.9"), VersionNumber("2.0"))
        XCTAssertLessThan(VersionNumber("1.2.3-beta"), VersionNumber("1.2.3"))
    }

    func testUnconfiguredRepositoryThrows() async {
        let checker = UpdateChecker(repository: nil)
        do {
            _ = try await checker.latestRelease(currentVersion: "1.0.0")
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error as? UpdateCheckError, .notConfigured)
        }
    }
}

final class ConfigurationStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigurationStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlueLinkTests-\(UUID().uuidString)", isDirectory: true)
        store = ConfigurationStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testMissingFile() {
        XCTAssertEqual(store.load(), .missing)
    }

    func testRoundTrip() throws {
        var configuration = AppConfiguration(
            isGloballyEnabled: true,
            devices: [ManagedDevice(id: DeviceID(raw: "AA-BB-CC-DD-EE-FF")!, cachedName: "Speaker")]
        )
        configuration.devices[0].isPaused = true
        try store.save(configuration)
        guard case .loaded(let loaded) = store.load() else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(loaded, configuration)
    }

    func testCorruptFileIsArchivedNotOverwrittenSilently() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.fileURL)
        guard case .corrupt = store.load() else {
            return XCTFail("expected corrupt")
        }
        let backup = try store.archiveCorruptFile()
        XCTAssertNotNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testUnknownVersionFileIsLeftUntouched() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = #"{"schemaVersion": 42, "isGloballyEnabled": true, "devices": []}"#
        try Data(original.utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), .unsupportedVersion(42))
        let onDisk = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, original)
    }
}

@MainActor
final class BluetoothEventMonitorTests: XCTestCase {
    func testLifecycleIsIdempotentAndUnregisters() {
        let monitor = BluetoothEventMonitor()
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.setManagedDevices([DeviceID(raw: "AA-BB-CC-DD-EE-FF")!])
        monitor.setManagedDevices([])
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }
}

final class AudioRouteControllerTests: XCTestCase {
    func testEnumeratesOutputDevicesWithoutSideEffects() throws {
        let devices = AudioRouteController().outputDevices()
        guard !devices.isEmpty else {
            throw XCTSkip("No audio output devices available in this session")
        }
        XCTAssertEqual(Set(devices.map(\.id)).count, devices.count)
        for device in devices {
            XCTAssertFalse(device.name.isEmpty)
        }
    }

    func testResolvesRealUIDButRejectsUnknown() throws {
        let devices = AudioRouteController().outputDevices()
        guard let first = devices.first else {
            throw XCTSkip("No audio output devices available in this session")
        }
        XCTAssertNotNil(AudioRouteController.deviceID(forUID: first.id))
        XCTAssertNil(AudioRouteController.deviceID(forUID: "dev.bluelink.missing.\(UUID().uuidString)"))
    }
}
