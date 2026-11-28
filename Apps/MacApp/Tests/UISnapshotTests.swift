import XCTest
import SwiftUI
import AppKit
@testable import BlueLink

/// Renders the real SwiftUI views through AppKit offscreen. This is test-only:
/// the app ships no debug window or test affordance. Images are written to
/// /tmp for manual inspection while every assertion checks the render worked.
@MainActor
final class UISnapshotTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/bluelink-shots", isDirectory: true)

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testMenuBarPanelSnapshot() throws {
        for (localeID, suffix) in [("en", "en"), ("zh-Hans", "zh")] {
            let model = AppModel()
            let view = MenuBarPanel()
                .environment(model)
                .environment(\.locale, Locale(identifier: localeID))
                .background(Color(nsColor: .windowBackgroundColor))
            let probe = NSHostingView(rootView: view)
            probe.frame.size.width = 348
            probe.layoutSubtreeIfNeeded()
            try render(
                view,
                size: CGSize(width: 348, height: probe.fittingSize.height),
                name: "menu-bar-panel-\(suffix)"
            )
        }
    }

    func testSettingsSnapshots() throws {
        for (localeID, suffix) in [("en", "en"), ("zh-Hans", "zh")] {
            let model = AppModel()
            let locale = Locale(identifier: localeID)
            let size = CGSize(width: 580, height: 560)

            let general = GeneralSettingsView()
                .environment(model)
                .environment(\.locale, locale)
                .background(Color(nsColor: .windowBackgroundColor))
            try render(general, size: size, name: "settings-general-\(suffix)")

            let devices = DevicesSettingsView()
                .environment(model)
                .environment(\.locale, locale)
                .background(Color(nsColor: .windowBackgroundColor))
            try render(devices, size: size, name: "settings-devices-\(suffix)")

            let diagnostics = DiagnosticsView()
                .environment(model)
                .environment(\.locale, locale)
                .background(Color(nsColor: .windowBackgroundColor))
            try render(diagnostics, size: size, name: "settings-diagnostics-\(suffix)")

            let about = AboutView()
                .environment(model)
                .environment(\.locale, locale)
                .background(Color(nsColor: .windowBackgroundColor))
            try render(about, size: size, name: "settings-about-\(suffix)")
        }
    }

    func testSettingsWindowAccessorTagsWindow() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsWindowAccessor().frame(width: 40, height: 40))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.identifier?.rawValue, "BlueLinkSettingsWindow")
        XCTAssertTrue(window.isVisible)
        window.close()
    }

    func testWindowFrostingMakesWindowTranslucent() async throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 580, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: Text("Probe")
                .frame(width: 580, height: 470)
                .blueLinkWindowFrosting()
        )
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        let effect = try XCTUnwrap(firstVisualEffect(in: hosting))
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        window.close()
    }

    func testDevicePickerUsesFrostedBackdrop() async throws {
        let model = AppModel()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 468, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: DevicePickerView().environment(model))
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        let effect = try XCTUnwrap(firstVisualEffect(in: hosting))
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        window.close()
    }

    func testDevicePickerSheetUsesFrostedBackdrop() async throws {
        let model = AppModel()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 468, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SheetProbe(model: model))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))

        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertFalse(sheet.isOpaque)
        XCTAssertEqual(sheet.backgroundColor, .clear)
        let content = try XCTUnwrap(sheet.contentView)
        let effect = try XCTUnwrap(firstVisualEffect(in: content))
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        window.close()
    }

    private func firstVisualEffect(in view: NSView) -> NSVisualEffectView? {
        if let effect = view as? NSVisualEffectView { return effect }
        for subview in view.subviews {
            if let effect = firstVisualEffect(in: subview) { return effect }
        }
        return nil
    }

    func testMenuBarIconAssetLoads() throws {
        let image = try XCTUnwrap(NSImage(named: "MenuBarIcon"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let rep = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
            "No bitmap for \(name)"
        )
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(data.count, 5_000, "Snapshot \(name) looks blank")
        window.contentView = nil
    }
}

private struct SheetProbe: View {
    let model: AppModel
    @State private var isPresented = true

    var body: some View {
        Color.clear.sheet(isPresented: $isPresented) {
            DevicePickerView().environment(model)
        }
    }
}
