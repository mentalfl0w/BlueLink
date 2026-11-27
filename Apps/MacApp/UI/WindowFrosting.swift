import AppKit
import SwiftUI

extension View {
    /// Native behind-window material for the Settings scene. Falls back to an
    /// opaque window when Reduce Transparency is enabled.
    func blueLinkWindowFrosting() -> some View {
        modifier(BlueLinkWindowFrosting())
    }
}

private struct BlueLinkWindowFrosting: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    FrostedMaterial()
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(contrast == .increased ? 0.32 : 0.10)
                }

                WindowAppearanceBridge(isOpaque: reduceTransparency)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

private struct FrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct WindowAppearanceBridge: NSViewRepresentable {
    let isOpaque: Bool

    func makeNSView(context: Context) -> WindowAppearanceProbe {
        let view = WindowAppearanceProbe(frame: .zero)
        view.wantsOpaqueWindow = isOpaque
        return view
    }

    func updateNSView(_ nsView: WindowAppearanceProbe, context: Context) {
        nsView.wantsOpaqueWindow = isOpaque
    }

    final class WindowAppearanceProbe: NSView {
        var wantsOpaqueWindow = false {
            didSet { apply(force: false) }
        }

        private weak var configuredWindow: NSWindow?
        private var configuredOpacity: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply(force: true)
        }

        func apply(force: Bool) {
            guard let window else { return }
            guard force || configuredWindow !== window || configuredOpacity != wantsOpaqueWindow else { return }
            configuredWindow = window
            configuredOpacity = wantsOpaqueWindow

            window.isOpaque = wantsOpaqueWindow
            window.backgroundColor = wantsOpaqueWindow ? .windowBackgroundColor : .clear
            window.invalidateShadow()
        }
    }
}
