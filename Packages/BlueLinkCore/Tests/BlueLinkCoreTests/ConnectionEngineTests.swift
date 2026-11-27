import XCTest
@testable import BlueLinkCore

final class ConnectionEngineTests: XCTestCase {
    private struct Harness {
        let engine: ConnectionEngine
        let transport: FakeTransport
        let clock: TestClock
    }

    private func makeHarness(
        configuration: AppConfiguration = TestFixtures.configuration(),
        system: SystemSnapshot = TestFixtures.awakeSystem(),
        connected: [DeviceID: Bool] = [TestFixtures.deviceA: false],
        retryPolicy: RetryPolicy = RetryPolicy(jitterFraction: 0)
    ) -> Harness {
        let transport = FakeTransport(connected: connected)
        let clock = TestClock()
        let engine = ConnectionEngine(
            configuration: configuration,
            system: system,
            transport: transport,
            clock: clock,
            retryPolicy: retryPolicy,
            randomUnit: { 0.5 }
        )
        return Harness(engine: engine, transport: transport, clock: clock)
    }

    // MARK: Launch and display transitions

    func testLaunchWhileAwakeConnects() async {
        let harness = makeHarness()
        await harness.engine.send(.start)
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
        let state = await deviceSnapshot(harness.engine)
        XCTAssertEqual(state?.desired, .connected)
    }

    func testLaunchWhileDisplayAsleepDoesNotConnect() async {
        let harness = makeHarness(system: TestFixtures.asleepSystem())
        await harness.engine.send(.start)
        try? await Task.sleep(for: .milliseconds(150))
        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 0)
    }

    func testDisplaySleepDisconnectsAndWakeReconnects() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }
        let disconnectCount = await harness.transport.disconnectCount(TestFixtures.deviceA)
        XCTAssertEqual(disconnectCount, 1)

        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
        let connectCount = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(connectCount, 1)
    }

    func testSystemSleepRespectsDisconnectSwitch() async {
        var policy = DevicePolicy()
        policy.disconnectOnSystemSleep = false
        let harness = makeHarness(
            configuration: TestFixtures.configuration([TestFixtures.managed(policy: policy)]),
            connected: [TestFixtures.deviceA: true]
        )
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        let sleeping = SystemSnapshot(power: .goingToSleep, display: .awake, session: .active, bluetooth: .available)
        await harness.engine.send(.systemChanged(sleeping))
        try? await Task.sleep(for: .milliseconds(150))
        let disconnectCount = await harness.transport.disconnectCount(TestFixtures.deviceA)
        XCTAssertEqual(disconnectCount, 0)
    }

    func testAwakeSystemWithoutWakeTransitionDoesNotResetManualOverride() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.engine.send(.manualDisconnect(TestFixtures.deviceA))
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }

        // Duplicate awake notifications must not clear the current-cycle override.
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        try? await Task.sleep(for: .milliseconds(150))
        let connectCount = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(connectCount, 0)
        let override = await deviceSnapshot(harness.engine)?.isManualOverrideActive
        XCTAssertEqual(override, true)

        // A genuine new wake cycle clears it.
        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
    }

    func testPauseKeepsConnectionButStopsReconnection() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        var configuration = TestFixtures.configuration()
        configuration.devices[0].isPaused = true
        await harness.engine.send(.configurationChanged(configuration))
        await waitUntil { await deviceSnapshot(harness.engine)?.desired == .unmanaged }

        let disconnectCount = await harness.transport.disconnectCount(TestFixtures.deviceA)
        XCTAssertEqual(disconnectCount, 0)

        await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        try? await Task.sleep(for: .milliseconds(150))
        let connectCount = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(connectCount, 0)

        configuration.devices[0].isPaused = false
        await harness.engine.send(.configurationChanged(configuration))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
    }

    // MARK: Unexpected disconnect

    func testUnexpectedDisconnectReconnectsWhenEnabled() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
    }

    func testUnexpectedDisconnectDoesNotReconnectWhenDisabled() async {
        var policy = DevicePolicy()
        policy.reconnectOnUnexpectedDisconnect = false
        let harness = makeHarness(
            configuration: TestFixtures.configuration([TestFixtures.managed(policy: policy)]),
            connected: [TestFixtures.deviceA: true]
        )
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }
        try? await Task.sleep(for: .milliseconds(150))
        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 0)
        let desired = await deviceSnapshot(harness.engine)?.desired
        XCTAssertEqual(desired, .unmanaged)
    }

    // MARK: Retry budget

    func testRetryBudgetIsBoundedAndBackedOff() async {
        let retryPolicy = RetryPolicy(maximumAttempts: 3, delays: [.seconds(1), .seconds(1)], jitterFraction: 0)
        let harness = makeHarness(retryPolicy: retryPolicy)
        await harness.transport.setFailures(TestFixtures.deviceA, count: 50)

        await harness.engine.send(.start)
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await harness.clock.pendingSleepCount() == 1 }

        await harness.clock.advance(by: .seconds(1))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 2 }
        await waitUntil { await harness.clock.pendingSleepCount() == 1 }

        await harness.clock.advance(by: .seconds(1))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 3 }
        await waitUntil { await deviceSnapshot(harness.engine)?.retryExhausted == true }

        try? await Task.sleep(for: .milliseconds(100))
        let pending = await harness.clock.pendingSleepCount()
        XCTAssertEqual(pending, 0)

        await harness.clock.advance(by: .seconds(60))
        try? await Task.sleep(for: .milliseconds(150))
        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 3)
        let failure = await deviceSnapshot(harness.engine)?.failure
        XCTAssertNotNil(failure)
    }

    func testNewWakeCycleRefreshesRetryBudget() async {
        let retryPolicy = RetryPolicy(maximumAttempts: 2, delays: [.seconds(1)], jitterFraction: 0)
        let harness = makeHarness(retryPolicy: retryPolicy)
        await harness.transport.setFailures(TestFixtures.deviceA, count: 50)

        await harness.engine.send(.start)
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await harness.clock.pendingSleepCount() == 1 }
        await harness.clock.advance(by: .seconds(1))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 2 }
        await waitUntil { await deviceSnapshot(harness.engine)?.retryExhausted == true }

        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 3 }
        await waitUntil { await harness.clock.pendingSleepCount() == 1 }
        await harness.clock.advance(by: .seconds(1))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 4 }
    }

    // MARK: In-flight intent changes

    func testManualDisconnectDuringConnectDisconnectsAfterLateCompletion() async {
        let harness = makeHarness()
        await harness.transport.setConnectDelay(.milliseconds(200))
        await harness.engine.send(.start)
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }

        await harness.engine.send(.manualDisconnect(TestFixtures.deviceA))
        await waitUntil(timeout: .seconds(3)) {
            await harness.transport.disconnectCount(TestFixtures.deviceA) == 1
        }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }
        let override = await deviceSnapshot(harness.engine)?.isManualOverrideActive
        XCTAssertEqual(override, true)
        let desired = await deviceSnapshot(harness.engine)?.desired
        XCTAssertNotEqual(desired, .connected)
    }

    // MARK: Multi-device isolation

    func testOneUnavailableDeviceDoesNotBlockAnother() async {
        let devices = [
            TestFixtures.managed(TestFixtures.deviceA, name: "A"),
            TestFixtures.managed(TestFixtures.deviceB, name: "B")
        ]
        let harness = makeHarness(
            configuration: TestFixtures.configuration(devices),
            connected: [TestFixtures.deviceA: false]
        )

        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine, TestFixtures.deviceA)?.observed == .connected }
        await waitUntil { await deviceSnapshot(harness.engine, TestFixtures.deviceB)?.observed == .unavailable }

        let stateB = await deviceSnapshot(harness.engine, TestFixtures.deviceB)
        XCTAssertNotNil(stateB?.failure)
        let stateA = await deviceSnapshot(harness.engine, TestFixtures.deviceA)
        XCTAssertEqual(stateA?.observed, .connected)
    }

    func testDuplicateNotificationsDoNotStartDuplicateOperations() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        for _ in 0..<5 {
            await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        }
        try? await Task.sleep(for: .milliseconds(150))
        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 0)
        let disconnects = await harness.transport.disconnectCount(TestFixtures.deviceA)
        XCTAssertEqual(disconnects, 0)
    }

    func testRemovedDeviceStopsAutomation() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: false])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.engine.send(.configurationChanged(TestFixtures.configuration([])))
        await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        try? await Task.sleep(for: .milliseconds(150))
        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 1)
        let devices = await harness.engine.snapshot().devices
        XCTAssertTrue(devices.isEmpty)
    }

    // MARK: Bluetooth recovery and late-operation races

    func testBluetoothRecoveryAfterLaunchConnects() async {
        let harness = makeHarness(system: TestFixtures.awakeSystem(bluetooth: .unknown))
        await harness.engine.send(.start)
        try? await Task.sleep(for: .milliseconds(100))
        let before = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(before, 0)

        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
    }

    func testDisplaySleepDuringConnectDisconnectsAfterCompletion() async {
        let harness = makeHarness()
        await harness.transport.setConnectDelay(.milliseconds(200))
        await harness.engine.send(.start)
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }

        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await waitUntil { await harness.transport.disconnectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }
    }

    func testWakeDuringDisconnectReconnects() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.transport.setDisconnectDelay(.milliseconds(200))
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await waitUntil { await harness.transport.disconnectCount(TestFixtures.deviceA) == 1 }
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))

        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 1 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
    }

    func testUnknownDisplayDoesNotCountAsWakeCycle() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
        await harness.engine.send(.manualDisconnect(TestFixtures.deviceA))
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .disconnected }

        let unknownDisplay = SystemSnapshot(
            power: .awake,
            display: .unknown,
            session: .active,
            bluetooth: .available
        )
        await harness.engine.send(.systemChanged(unknownDisplay))
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        try? await Task.sleep(for: .milliseconds(150))

        let count = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(count, 0, "unknown→awake must not clear the current-cycle manual override")
        let state = await deviceSnapshot(harness.engine)
        XCTAssertTrue(state?.isManualOverrideActive == true)
    }

    func testUnexpectedDropRateIsCappedUntilWakeCycle() async {
        let harness = makeHarness(connected: [TestFixtures.deviceA: true])
        await harness.engine.send(.start)
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }

        for attempt in 1...3 {
            await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
            await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
            await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == attempt }
            await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
        }

        await harness.transport.simulateExternalDisconnect(TestFixtures.deviceA)
        await harness.engine.send(.externalDeviceChange(TestFixtures.deviceA))
        await waitUntil {
            let state = await deviceSnapshot(harness.engine)
            return state?.observed == .disconnected && state?.retryExhausted == true
        }
        let limited = await deviceSnapshot(harness.engine)
        XCTAssertEqual(limited?.failure?.kind, .reconnectRateLimited)
        let countAtLimit = await harness.transport.connectCount(TestFixtures.deviceA)
        XCTAssertEqual(countAtLimit, 3)

        await harness.engine.send(.systemChanged(TestFixtures.asleepSystem()))
        await harness.engine.send(.systemChanged(TestFixtures.awakeSystem()))
        await waitUntil { await harness.transport.connectCount(TestFixtures.deviceA) == 4 }
        await waitUntil { await deviceSnapshot(harness.engine)?.observed == .connected }
    }
}

extension FakeTransport {
    func setConnectDelay(_ value: Duration) async {
        connectDelay = value
    }

    func setDisconnectDelay(_ value: Duration) async {
        disconnectDelay = value
    }
}

private func deviceSnapshot(
    _ engine: ConnectionEngine,
    _ id: DeviceID = TestFixtures.deviceA
) async -> DeviceState? {
    await engine.snapshot().devices.first { $0.id == id }
}
