import SwiftUI
import AppKit
import BlueLinkCore
import MacIntegration

struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var isPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.configuration.devices.isEmpty {
                emptyState
            } else if model.engineState.devices.isEmpty {
                ProgressView("Loading devices…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                deviceList
            }

            Divider()
            footer
        }
        .frame(width: 348)
        .task {
            model.refresh()
        }
        .sheet(isPresented: $isPickerPresented) {
            DevicePickerView()
                .environment(model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("BlueLink")
                    .font(.headline)
                Text(model.configuration.isGloballyEnabled
                     ? LocalizedStringKey("Automatic management")
                     : LocalizedStringKey("Automatic management off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Automatic management",
                isOn: Binding(
                    get: { model.configuration.isGloballyEnabled },
                    set: { model.setGlobalEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No devices yet")
                .font(.headline)
            Text("Choose a paired Bluetooth device. BlueLink connects and disconnects it with your display.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Device…") {
                isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
    }

    private var deviceList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.engineState.devices) { device in
                    DeviceRow(device: device, system: model.engineState.system, globallyEnabled: model.configuration.isGloballyEnabled)
                    if device.id != model.engineState.devices.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .frame(height: deviceListHeight)
    }

    /// `MenuBarExtra` gives a bare `ScrollView` no intrinsic height, so size the
    /// list from the known device count (at least one row) and scroll beyond five.
    private var deviceListHeight: CGFloat {
        let count = max(model.engineState.devices.count, model.configuration.devices.count)
        return min(max(CGFloat(count) * 72, 72), 322)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                isPickerPresented = true
                Task { await model.refreshPairedDevices() }
            } label: {
                Label("Add Device", systemImage: "plus")
            }

            Spacer()

            Button {
                NSApp.activate()
                openSettings()
                SettingsWindowPresenter.bringForward()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .accessibilityLabel("Quit BlueLink")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: DeviceState
    let system: SystemSnapshot
    let globallyEnabled: Bool

    private var status: DeviceStatus {
        DeviceStatusPresentation.status(for: device, system: system, globallyEnabled: globallyEnabled)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
                if let failure = device.failure, device.retryExhausted, device.observed != .connected {
                    Text(failure.detail ?? String(localized: "Open Diagnostics for details."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if DeviceStatusPresentation.canDisconnect(device) {
                    Button {
                        model.disconnect(device.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help("Disconnect now")
                    .accessibilityLabel("Disconnect \(device.name)")
                } else if DeviceStatusPresentation.canConnect(device) {
                    Button {
                        if device.retryExhausted || device.failure != nil {
                            model.retry(device.id)
                        } else {
                            model.connect(device.id)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .help("Connect now")
                    .accessibilityLabel("Connect \(device.name)")
                }

                Button {
                    model.setPaused(!device.isPaused, for: device.id)
                } label: {
                    Image(systemName: device.isPaused ? "play.circle" : "pause.circle")
                }
                .help(device.isPaused
                      ? Text("Resume automatic management")
                      : Text("Pause automatic management"))
                .accessibilityLabel(Text(device.isPaused
                                         ? LocalizedStringKey("Resume \(device.name)")
                                         : LocalizedStringKey("Pause \(device.name)")))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusTint)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected, .connectedAudioReady: .green
        case .connecting, .disconnecting, .settling, .reconnecting: .blue
        case .connectedAudioUnavailable, .failed, .unavailable: .orange
        case .manualOverride, .paused, .automationOff, .waitingForWake, .disconnected: .secondary
        }
    }

    private var statusTint: Color {
        switch status {
        case .failed, .unavailable: .orange
        default: .secondary
        }
    }

    private var statusText: LocalizedStringResource {
        switch status {
        case .automationOff: "Automatic management off"
        case .paused: "Paused"
        case .connecting: "Connecting…"
        case .disconnecting: "Disconnecting…"
        case .settling: "Confirming connection…"
        case .connected: "Connected"
        case .connectedAudioReady: "Connected · audio ready"
        case .connectedAudioUnavailable: "Connected · preferred audio unavailable"
        case .reconnecting(let attempt): "Reconnecting · attempt \(attempt)"
        case .failed(let kind): DeviceStatusPresentation.failureSummary(kind)
        case .manualOverride: "Disconnected for this wake cycle"
        case .unavailable: "Not available"
        case .waitingForWake: "Waiting for the display"
        case .disconnected: "Disconnected"
        }
    }
}
