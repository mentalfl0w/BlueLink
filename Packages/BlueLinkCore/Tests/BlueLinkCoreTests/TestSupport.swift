import Foundation
import XCTest
@testable import BlueLinkCore

enum TestFixtures {
    static let deviceA = DeviceID(raw: "AA-BB-CC-DD-EE-FF")!
    static let deviceB = DeviceID(raw: "11-22-33-44-55-66")!

    static func awakeSystem(bluetooth: BluetoothAvailability = .available) -> SystemSnapshot {
        SystemSnapshot(power: .awake, display: .awake, session: .active, bluetooth: bluetooth)
    }

    static func asleepSystem() -> SystemSnapshot {
        SystemSnapshot(power: .awake, display: .asleep, session: .active, bluetooth: .available)
    }

    static func managed(
        _ id: DeviceID = deviceA,
        name: String = "Test Speaker",
        policy: DevicePolicy = DevicePolicy(),
        paused: Bool = false
    ) -> ManagedDevice {
        ManagedDevice(id: id, cachedName: name, policy: policy, isPaused: paused)
    }

    static func configuration(
        _ devices: [ManagedDevice] = [managed()],
        enabled: Bool = true
    ) -> AppConfiguration {
        AppConfiguration(isGloballyEnabled: enabled, devices: devices)
    }
}

actor FakeTransport: BluetoothTransport {
    enum Failure: Error, Equatable {
        case operationFailed
    }

    private(set) var connected: [DeviceID: Bool]
    private(set) var connectCounts: [DeviceID: Int] = [:]
    private(set) var disconnectCounts: [DeviceID: Int] = [:]
    private(set) var connectTimeouts: [DeviceID: Duration] = [:]
    private var failuresRemaining: [DeviceID: Int] = [:]
    var connectDelay: Duration = .zero
    var disconnectDelay: Duration = .zero
    var paired: [PairedDevice] = []

    init(connected: [DeviceID: Bool] = [:]) {
        self.connected = connected
    }

    func pairedDevices() async throws -> [PairedDevice] { paired }

    func isConnected(_ id: DeviceID) async throws -> Bool {
        guard let state = connected[id] else { throw BluetoothTransportError.deviceNotFound }
        return state
    }

    func connect(_ id: DeviceID, timeout: Duration) async throws {
        connectCounts[id, default: 0] += 1
        connectTimeouts[id] = timeout
        let delay = connectDelay
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let remaining = failuresRemaining[id], remaining > 0 {
            failuresRemaining[id] = remaining - 1
            throw Failure.operationFailed
        }
        guard connected[id] != nil else { throw BluetoothTransportError.deviceNotFound }
        connected[id] = true
    }

    func disconnect(_ id: DeviceID, timeout: Duration) async throws {
        disconnectCounts[id, default: 0] += 1
        let delay = disconnectDelay
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        guard connected[id] != nil else { throw BluetoothTransportError.deviceNotFound }
        connected[id] = false
    }

    func configure(_ id: DeviceID, initiallyConnected: Bool) {
        connected[id] = initiallyConnected
    }

    func setFailures(_ id: DeviceID, count: Int) {
        failuresRemaining[id] = count
    }

    func simulateExternalDisconnect(_ id: DeviceID) {
        connected[id] = false
    }

    func connectCount(_ id: DeviceID) -> Int { connectCounts[id] ?? 0 }
    func disconnectCount(_ id: DeviceID) -> Int { disconnectCounts[id] ?? 0 }
}

enum TestWait {
    static func until(
        timeout: Duration = .seconds(5),
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimeoutError.conditionNotMet
    }

    enum TimeoutError: Error { case conditionNotMet }
}

extension XCTestCase {
    func waitUntil(
        timeout: Duration = .seconds(5),
        message: @autoclosure () -> String = "condition not met",
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        do {
            try await TestWait.until(timeout: timeout, condition)
        } catch {
            XCTFail(message())
        }
    }
}
