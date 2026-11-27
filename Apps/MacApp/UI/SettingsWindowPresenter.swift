import AppKit
import SwiftUI

/// Brings the SwiftUI Settings window to the front. A menu bar-only app is not
/// automatically activated when `openSettings` creates the window, so without
/// this the window can open behind the current app.
@MainActor
enum SettingsWindowPresenter {
    private static let identifier = NSUserInterfaceItemIdentifier("BlueLinkSettingsWindow")

    static func bringForward() {
        NSApp.activate()
        raiseSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            raiseSettingsWindow()
        }
    }

    static func adopt(_ window: NSWindow) {
        window.identifier = identifier
        raise(window)
    }

    private static func raiseSettingsWindow() {
        let identified = NSApp.windows.first { $0.identifier == identifier }
        // Fallback for the first frame, before the accessor has tagged the window.
        let fallback = NSApp.windows.first {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
        }
        if let window = identified ?? fallback {
            raise(window)
        }
    }

    private static func raise(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// Tags the hosting NSWindow and raises it when the Settings scene appears.
struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowProbeView()
        view.onWindow = { window in
            SettingsWindowPresenter.adopt(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowProbeView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}
