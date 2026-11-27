import XCTest
import BlueLinkCore
@testable import BlueLink

final class DeviceStatusPresentationTests: XCTestCase {
    private let id = DeviceID(raw: "AA-BB-CC-DD-EE-FF")!

    private func state(
        observed: ObservedConnection = .disconnected,
        operation: OperationPhase = .idle,
        desired: DesiredConnection = .connected,
        paused: Bool = false,
        failure: DeviceFailure? = nil,
        retryAttempt: Int = 0,
        retryExhausted: Bool = false,
        manualOverride: Bool = false,
        audioReady: Bool? = nil
    ) -> DeviceState {
        DeviceState(
            id: id,
            name: "Test Device",
            policy: DevicePolicy(),
            isPaused: paused,
            desired: desired,
            observed: observed,
            operation: operation,
            failure: failure,
            retryAttempt: retryAttempt,
            retryExhausted: retryExhausted,
            isManualOverrideActive: manualOverride,
            audioReady: audioReady
        )
    }

    private func system(display: DisplayState = .awake, power: PowerState = .awake) -> SystemSnapshot {
        SystemSnapshot(power: power, display: display, session: .active, bluetooth: .available)
    }

    func testGlobalOffWins() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(), system: system(), globallyEnabled: false),
            .automationOff
        )
    }

    func testPauseWinsBeforeConnectionState() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(observed: .connected, paused: true), system: system(), globallyEnabled: true),
            .paused
        )
    }

    func testOperationPhasesAreReported() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(operation: .connecting), system: system(), globallyEnabled: true),
            .connecting
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(observed: .connected, operation: .disconnecting), system: system(), globallyEnabled: true),
            .disconnecting
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(operation: .settling), system: system(), globallyEnabled: true),
            .settling
        )
    }

    func testConnectedAudioStates() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(observed: .connected), system: system(), globallyEnabled: true),
            .connected
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(observed: .connected, audioReady: true), system: system(), globallyEnabled: true),
            .connectedAudioReady
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(for: state(observed: .connected, audioReady: false), system: system(), globallyEnabled: true),
            .connectedAudioUnavailable
        )
    }

    func testFailedOnlyAfterBudgetExhausted() {
        let failure = DeviceFailure(kind: .connectFailed, occurredAt: Date())
        XCTAssertEqual(
            DeviceStatusPresentation.status(
                for: state(failure: failure, retryAttempt: 2),
                system: system(),
                globallyEnabled: true
            ),
            .reconnecting(attempt: 2)
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(
                for: state(failure: failure, retryAttempt: 2, retryExhausted: true),
                system: system(),
                globallyEnabled: true
            ),
            .failed(.connectFailed)
        )
    }

    func testManualOverrideAndUnavailable() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(
                for: state(desired: .unmanaged, manualOverride: true),
                system: system(),
                globallyEnabled: true
            ),
            .manualOverride
        )
        XCTAssertEqual(
            DeviceStatusPresentation.status(
                for: state(observed: .unavailable),
                system: system(),
                globallyEnabled: true
            ),
            .unavailable
        )
    }

    func testWaitingForWakeWhenDisplayAsleep() {
        XCTAssertEqual(
            DeviceStatusPresentation.status(
                for: state(desired: .disconnected),
                system: system(display: .asleep),
                globallyEnabled: true
            ),
            .waitingForWake
        )
    }

    func testActionAvailability() {
        XCTAssertTrue(DeviceStatusPresentation.canDisconnect(state(observed: .connected)))
        XCTAssertFalse(DeviceStatusPresentation.canConnect(state(observed: .connected)))
        XCTAssertTrue(DeviceStatusPresentation.canConnect(state(observed: .disconnected)))
        XCTAssertFalse(DeviceStatusPresentation.canConnect(state(observed: .disconnected, operation: .connecting)))
    }
}
