import SwiftUI
import BlueLinkCore
import MacIntegration

struct DevicesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    @State private var pendingRemoval: DeviceState?

    var body: some View {
        VStack(spacing: 0) {
            if model.configuration.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No managed devices")
                        .font(.headline)
                    Text("Add a paired Bluetooth device to control it with your display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Add Device…") {
                        isPickerPresented = true
                        Task { await model.refreshPairedDevices() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.engineState.devices) { device in
                            deviceCard(device)
                        }
                    }
                    .padding(14)
                }
            }

            Divider()
            HStack {
                Button {
                    isPickerPresented = true
                    Task { await model.refreshPairedDevices() }
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
                Spacer()
                Text("\(model.configuration.devices.count) managed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $isPickerPresented) {
            DevicePickerView()
                .environment(model)
        }
        .confirmationDialog(
            "Remove this device?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { device in
            Button("Remove \(device.name)", role: .destructive) {
                model.removeDevice(device.id)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { device in
            Text("BlueLink stops managing \(device.name). Its current connection is left unchanged.")
        }
        .task {
            model.refreshAudioOutputs()
        }
    }

    private func deviceCard(_ device: DeviceState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusDescription(device))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Automatic management", isOn: Binding(
                    get: { !device.isPaused },
                    set: { model.setPaused(!$0, for: device.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(device.isPaused ? "Resume automatic management" : "Pause automatic management")

                Menu {
                    Button("Connect Now") { model.connect(device.id) }
                    Button("Disconnect Now") { model.disconnect(device.id) }
                    Divider()
                    Button("Remove Device…", role: .destructive) {
                        pendingRemoval = device
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(device.name)")
            }

            Divider()

            policyToggle(
                "Connect when the display wakes",
                isOn: Binding(
                    get: { device.policy.connectOnDisplayWake },
                    set: { value in
                        var policy = device.policy
                        policy.connectOnDisplayWake = value
                        model.updatePolicy(policy, for: device.id)
                    }
                )
            )
            policyToggle(
                "Disconnect when the display sleeps",
                isOn: Binding(
                    get: { device.policy.disconnectOnDisplaySleep },
                    set: { value in
                        var policy = device.policy
                        policy.disconnectOnDisplaySleep = value
                        model.updatePolicy(policy, for: device.id)
                    }
                )
            )
            policyToggle(
                "Reconnect after an unexpected drop",
                isOn: Binding(
                    get: { device.policy.reconnectOnUnexpectedDisconnect },
                    set: { value in
                        var policy = device.policy
                        policy.reconnectOnUnexpectedDisconnect = value
                        model.updatePolicy(policy, for: device.id)
                    }
                )
            )
            policyToggle(
                "Disconnect on system sleep",
                isOn: Binding(
                    get: { device.policy.disconnectOnSystemSleep },
                    set: { value in
                        var policy = device.policy
                        policy.disconnectOnSystemSleep = value
                        model.updatePolicy(policy, for: device.id)
                    }
                )
            )

            HStack {
                Text("Preferred audio output")
                    .font(.callout)
                Spacer()
                Picker("Preferred audio output", selection: Binding(
                    get: { device.policy.preferredAudioUID ?? "" },
                    set: { value in
                        var policy = device.policy
                        policy.preferredAudioUID = value.isEmpty ? nil : value
                        model.updatePolicy(policy, for: device.id)
                    }
                )) {
                    Text("System default").tag("")
                    ForEach(model.audioOutputs) { output in
                        Text(output.name).tag(output.id)
                    }
                    if let uid = device.policy.preferredAudioUID,
                       !model.audioOutputs.contains(where: { $0.id == uid }) {
                        Text("Unavailable output").tag(uid)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            if let failure = device.failure {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(failureDescription(failure))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if device.retryExhausted {
                        Button("Retry") { model.retry(device.id) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func policyToggle(
        _ title: LocalizedStringResource,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.callout)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func statusDescription(_ device: DeviceState) -> String {
        let status = DeviceStatusPresentation.status(
            for: device,
            system: model.engineState.system,
            globallyEnabled: model.configuration.isGloballyEnabled
        )
        switch status {
        case .connected: return String(localized: "Connected")
        case .connectedAudioReady: return String(localized: "Connected · audio ready")
        case .connectedAudioUnavailable: return String(localized: "Connected · preferred audio unavailable")
        case .connecting: return String(localized: "Connecting…")
        case .disconnecting: return String(localized: "Disconnecting…")
        case .settling: return String(localized: "Confirming connection…")
        case .paused: return String(localized: "Automatic management paused")
        case .automationOff: return String(localized: "Automatic management off")
        case .manualOverride: return String(localized: "Disconnected for this wake cycle")
        case .waitingForWake: return String(localized: "Waiting for the display")
        case .unavailable: return String(localized: "Not available")
        case .disconnected: return String(localized: "Disconnected")
        case .reconnecting(let attempt): return String(localized: "Reconnecting · attempt \(attempt)")
        case .failed(let kind): return String(localized: DeviceStatusPresentation.failureDetail(kind))
        }
    }

    private func failureDescription(_ failure: DeviceFailure) -> String {
        String(localized: DeviceStatusPresentation.failureDetail(failure.kind))
    }
}
