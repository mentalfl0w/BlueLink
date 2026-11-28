import XCTest
import BlueLinkCore
@testable import BlueLink

@MainActor
final class LocalizationTests: XCTestCase {
    private let zhHans = Locale(identifier: "zh-Hans")

    func testPrimaryInterfaceStrings() {
        XCTAssertEqual(String(localized: "Automatic management", bundle: .main, locale: zhHans), "自动管理")
        XCTAssertEqual(String(localized: "No devices yet", bundle: .main, locale: zhHans), "尚未添加设备")
        XCTAssertEqual(String(localized: "Preferred audio output", bundle: .main, locale: zhHans), "首选音频输出")
        XCTAssertEqual(String(localized: "Couldn't connect.", bundle: .main, locale: zhHans), "无法连接。")
        XCTAssertEqual(String(localized: "Waiting for the display", bundle: .main, locale: zhHans), "等待显示屏")
        XCTAssertEqual(String(localized: "Recent events", bundle: .main, locale: zhHans), "最近事件")
        XCTAssertEqual(String(localized: "Check for updates automatically", bundle: .main, locale: zhHans), "自动检查更新")
        XCTAssertEqual(String(localized: "Automatically download updates", bundle: .main, locale: zhHans), "自动下载更新")
    }

    func testInterpolatedStatusStrings() {
        let attempt = 2
        XCTAssertEqual(
            String(localized: "Reconnecting · attempt \(attempt)", bundle: .main, locale: zhHans),
            "正在重连 · 第 2 次尝试"
        )
        let count = 3
        XCTAssertEqual(
            String(localized: "\(count) managed", bundle: .main, locale: zhHans),
            "已管理 3"
        )
        let version = "1.2.0"
        XCTAssertEqual(
            String(localized: "Version \(version) is available", bundle: .main, locale: zhHans),
            "版本 1.2.0 可用"
        )
    }

    func testDiagnosticsDeviceDetailIsLocalized() throws {
        let id = try XCTUnwrap(DeviceID(raw: "AA-BB-CC-DD-EE-FF"))
        let device = DeviceState(
            id: id,
            name: "Test Device",
            policy: DevicePolicy(),
            isPaused: true,
            desired: .connected,
            observed: .disconnected,
            operation: .idle,
            failure: nil,
            retryAttempt: 2,
            retryExhausted: false,
            isManualOverrideActive: true,
            audioReady: nil
        )
        let detail = DiagnosticsPresentation.deviceDetail(for: device, locale: zhHans)
        XCTAssertEqual(
            detail,
            "目标 已连接 · 实际 已断开 · 操作 空闲 · 重试 2 · 已暂停 · 手动干预"
        )
        for rawValue in ["connected", "disconnected", "idle", "retry", "paused", "manual override"] {
            XCTAssertFalse(detail.contains(rawValue), "raw English value leaked: \(rawValue)")
        }
    }

    func testBluetoothUsageDescriptionIsLocalized() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(
            bundle.localizedInfoDictionary?["NSBluetoothAlwaysUsageDescription"] as? String,
            "BlueLink 会连接和断开你选择的蓝牙设备。"
        )
    }
}
