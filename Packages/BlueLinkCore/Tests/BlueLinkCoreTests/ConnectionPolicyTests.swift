import XCTest
@testable import BlueLinkCore

final class ConnectionPolicyTests: XCTestCase {
    private func decide(
        system: SystemSnapshot = TestFixtures.awakeSystem(),
        device: ManagedDevice = TestFixtures.managed(),
        observed: ObservedConnection = .disconnected,
        operation: OperationPhase = .idle,
        manualOverride: Bool = false,
        trigger: ReconcileTrigger,
        enabled: Bool = true
    ) -> PolicyDecision {
        ConnectionPolicy.decide(
            PolicyInput(
                isGloballyEnabled: enabled,
                device: device,
                system: system,
                observed: observed,
                operation: operation,
                manualDisconnectInCurrentCycle: manualOverride,
                trigger: trigger
            )
        )
    }

    func testUnmanagedWhenGloballyDisabled() {
        XCTAssertEqual(decide(trigger: .wakeCycle, enabled: false), .unmanaged)
    }

    func testUnmanagedWhenPaused() {
        let device = TestFixtures.managed(paused: true)
        XCTAssertEqual(decide(device: device, trigger: .wakeCycle), .unmanaged)
    }

    func testUnmanagedWhenSessionInactive() {
        let system = SystemSnapshot(power: .awake, display: .awake, session: .inactive, bluetooth: .available)
        XCTAssertEqual(decide(system: system, trigger: .wakeCycle), .unmanaged)
    }

    func testUnmanagedWhenBluetoothUnavailableOrUnknown() {
        for availability in [BluetoothAvailability.unavailable, .unauthorized, .unknown] {
            let system = TestFixtures.awakeSystem(bluetooth: availability)
            XCTAssertEqual(decide(system: system, trigger: .wakeCycle), .unmanaged)
        }
    }

    func testSystemSleepDisconnectsOnlyWhenEnabled() {
        let sleeping = SystemSnapshot(power: .goingToSleep, display: .awake, session: .active, bluetooth: .available)
        XCTAssertEqual(decide(system: sleeping, trigger: .none), .disconnect)

        var policy = DevicePolicy()
        policy.disconnectOnSystemSleep = false
        XCTAssertEqual(decide(system: sleeping, device: TestFixtures.managed(policy: policy), trigger: .none), .unmanaged)
    }

    func testUnknownPowerNeverActs() {
        let system = SystemSnapshot(power: .unknown, display: .awake, session: .active, bluetooth: .available)
        XCTAssertEqual(decide(system: system, trigger: .wakeCycle), .unmanaged)
    }

    func testUnknownDisplayNeverActs() {
        let system = SystemSnapshot(power: .awake, display: .unknown, session: .active, bluetooth: .available)
        XCTAssertEqual(decide(system: system, trigger: .wakeCycle), .unmanaged)
    }

    func testDisplaySleepDisconnectsOnlyWhenEnabled() {
        let asleep = TestFixtures.asleepSystem()
        XCTAssertEqual(decide(system: asleep, trigger: .none), .disconnect)

        var policy = DevicePolicy()
        policy.disconnectOnDisplaySleep = false
        XCTAssertEqual(decide(system: asleep, device: TestFixtures.managed(policy: policy), trigger: .none), .unmanaged)
    }

    func testManualOverrideSuppressesAutomaticConnect() {
        XCTAssertEqual(decide(manualOverride: true, trigger: .wakeCycle), .unmanaged)
        XCTAssertEqual(decide(manualOverride: true, trigger: .unexpectedDisconnect), .unmanaged)
        XCTAssertEqual(decide(manualOverride: true, trigger: .configurationChange), .unmanaged)
    }

    func testWakeCycleRespectsConnectSwitch() {
        XCTAssertEqual(decide(trigger: .wakeCycle), .connect)

        var policy = DevicePolicy()
        policy.connectOnDisplayWake = false
        XCTAssertEqual(decide(device: TestFixtures.managed(policy: policy), trigger: .wakeCycle), .unmanaged)
    }

    func testLaunchAndConfigurationChangeUseConnectSwitch() {
        XCTAssertEqual(decide(trigger: .launch), .connect)
        XCTAssertEqual(decide(trigger: .configurationChange), .connect)
        XCTAssertEqual(decide(trigger: .bluetoothRecovered), .connect)
    }

    func testUnexpectedDisconnectUsesReconnectSwitch() {
        XCTAssertEqual(decide(trigger: .unexpectedDisconnect), .connect)

        var policy = DevicePolicy()
        policy.reconnectOnUnexpectedDisconnect = false
        XCTAssertEqual(
            decide(device: TestFixtures.managed(policy: policy), trigger: .unexpectedDisconnect),
            .unmanaged
        )
    }

    func testExplicitRetryConnectsRegardlessOfWakeSwitch() {
        var policy = DevicePolicy()
        policy.connectOnDisplayWake = false
        XCTAssertEqual(decide(device: TestFixtures.managed(policy: policy), trigger: .explicitRetry), .connect)
    }

    func testPassiveTriggerPreservesIntent() {
        XCTAssertEqual(decide(trigger: .none), .preserve)
    }

    func testSwitchesAreIndependent() {
        var policy = DevicePolicy()
        policy.disconnectOnDisplaySleep = false
        let asleep = TestFixtures.asleepSystem()
        XCTAssertEqual(decide(system: asleep, device: TestFixtures.managed(policy: policy), trigger: .wakeCycle), .unmanaged)

        policy.disconnectOnDisplaySleep = true
        policy.connectOnDisplayWake = false
        XCTAssertEqual(decide(system: asleep, device: TestFixtures.managed(policy: policy), trigger: .none), .disconnect)
    }
}
