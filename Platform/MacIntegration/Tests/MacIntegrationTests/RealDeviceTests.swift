import XCTest
import BlueLinkCore
@testable import MacIntegration

/// Opt-in hardware integration test. It never runs in CI and never hardcodes a
/// Bluetooth address; the operator supplies an already-paired device:
///
///   BLUELINK_REAL_DEVICE=1 \
///   BLUELINK_TEST_DEVICE_ID=AA-BB-CC-DD-EE-FF \
///   BLUELINK_TEST_DEVICE_NAME="Speaker" \
///   swift test --package-path Platform/MacIntegration --filter RealDeviceTests
///
/// The test restores the connection state it found on entry.
final class RealDeviceTests: XCTestCase {
    func testEngineConnectsAndDisconnectsRealDevice() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["BLUELINK_REAL_DEVICE"] == "1",
            "Set BLUELINK_REAL_DEVICE=1 to run hardware tests."
        )
        let rawID = try XCTUnwrap(environment["BLUELINK_TEST_DEVICE_ID"])
        let id = try XCTUnwrap(DeviceID(raw: rawID))
        let name = environment["BLUELINK_TEST_DEVICE_NAME"] ?? id.address

        let transport = IOBluetoothTransport()
        guard await transport.availability() == .available else {
            throw XCTSkip("Bluetooth is not available.")
        }
        let initialState = try await transport.isConnected(id)

        let configuration = AppConfiguration(
            devices: [ManagedDevice(id: id, cachedName: name)]
        )
        let system = SystemSnapshot(power: .awake, display: .awake, session: .active, bluetooth: .available)
        let engine = ConnectionEngine(
            configuration: configuration,
            system: system,
            transport: transport,
            connectTimeout: .seconds(20),
            disconnectTimeout: .seconds(8)
        )

        await engine.send(.start)
        try await waitFor(engine, id: id, observed: .connected, message: "initial launch connect")
        let connectedAfterLaunch = try await transport.isConnected(id)
        XCTAssertTrue(connectedAfterLaunch, "Engine reported connected but IOBluetooth did not.")

        await engine.send(.manualDisconnect(id))
        try await waitFor(engine, id: id, observed: .disconnected, message: "manual disconnect")
        let connectedAfterDisconnect = try await transport.isConnected(id)
        XCTAssertFalse(connectedAfterDisconnect, "Manual disconnect left the device connected.")

        await engine.send(.manualConnect(id))
        try await waitFor(engine, id: id, observed: .connected, message: "manual connect")
        let connectedAfterManualConnect = try await transport.isConnected(id)
        XCTAssertTrue(connectedAfterManualConnect, "Manual connect did not reach IOBluetooth.")

        // Restore the state observed before the test.
        await engine.send(.manualDisconnect(id))
        try await waitFor(engine, id: id, observed: .disconnected, message: "cleanup disconnect")
        if initialState {
            await engine.send(.manualConnect(id))
            try await waitFor(engine, id: id, observed: .connected, message: "restore initial connection")
        }
    }

    private func waitFor(
        _ engine: ConnectionEngine,
        id: DeviceID,
        observed: ObservedConnection,
        message: String,
        timeout: Duration = .seconds(30)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let state = await engine.snapshot()
            if let device = state.devices.first(where: { $0.id == id }) {
                if device.observed == observed, device.operation == .idle {
                    return
                }
                if device.retryExhausted {
                    XCTFail("\(message): retries exhausted (\(String(describing: device.failure)))")
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("\(message): timed out waiting for \(observed.rawValue)")
    }
}
