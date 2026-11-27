import SwiftUI
import BlueLinkCore
import MacIntegration

struct DevicePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pendingInputDevice: PairedDevice?

    private var availableDevices: [PairedDevice] {
        model.pairedDevices.filter { paired in
            guard model.configuration.device(paired.id) == nil else { return false }
            guard model.showInputDevices || !paired.isInputDevice else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || paired.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a Device")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.refreshPairedDevices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoadingPairedDevices)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Text("Pair the device in System Settings → Bluetooth first. BlueLink never pairs or unpairs devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search devices", text: $searchText)
                    .textFieldStyle(.plain)
                Toggle("Show input devices", isOn: Binding(
                    get: { model.showInputDevices },
                    set: { model.showInputDevices = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Divider()

            Group {
                if model.isLoadingPairedDevices && model.pairedDevices.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableDevices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("No devices to add")
                            .font(.headline)
                        Text(model.showInputDevices
                             ? LocalizedStringKey("Every paired device is already managed.")
                             : LocalizedStringKey("Show input devices if you really want to manage a keyboard or trackpad."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(availableDevices) { paired in
                                row(for: paired)
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                if model.configurationIssue != nil {
                    Label("Configuration needs attention", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 468, height: 440)
        .blueLinkWindowFrosting()
        .task {
            await model.refreshPairedDevices()
        }
        .confirmationDialog(
            "Manage an input device?",
            isPresented: Binding(
                get: { pendingInputDevice != nil },
                set: { if !$0 { pendingInputDevice = nil } }
            ),
            presenting: pendingInputDevice
        ) { paired in
            Button("Manage \(paired.name)") {
                model.addDevice(paired)
                pendingInputDevice = nil
            }
            Button("Cancel", role: .cancel) {
                pendingInputDevice = nil
            }
        } message: { paired in
            Text("\(paired.name) is an input device. Disconnecting it can make the keyboard or trackpad stop working until it reconnects.")
        }
    }

    private func row(for paired: PairedDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: paired.isInputDevice ? "keyboard" : "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(paired.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if paired.isConnected {
                        Text("Connected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(paired.isInputDevice
                     ? LocalizedStringKey("Input device")
                     : (paired.isAudioDevice
                        ? LocalizedStringKey("Audio device")
                        : LocalizedStringKey("Bluetooth device")))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Add") {
                if paired.isInputDevice {
                    pendingInputDevice = paired
                } else {
                    model.addDevice(paired)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
