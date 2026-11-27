import SwiftUI
import BlueLinkCore
import MacIntegration

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var entries: [DiagnosticsEntry] = []
    @State private var isExporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                systemSection
                devicesSection
                if let issue = model.configurationIssue {
                    configurationSection(issue)
                }
                logSection
            }
            .padding(16)
        }
        .task { await reload() }
    }

    private var systemSection: some View {
        GroupBox {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
                row("Power", systemPowerText)
                row("Display", displayText)
                row("Session", sessionText)
                row("Bluetooth", bluetoothText)
                row("Automatic management", model.configuration.isGloballyEnabled ? "On" : "Off")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("System", systemImage: "desktopcomputer")
        }
    }

    private var devicesSection: some View {
        GroupBox {
            if model.engineState.devices.isEmpty {
                Text("No managed devices")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.engineState.devices) { device in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name)
                                .font(.callout.weight(.medium))
                            Text(deviceDetail(device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let failure = device.failure {
                                Text(DeviceStatusPresentation.failureDetail(failure.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(6)
            }
        } label: {
            Label("Devices", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    private func configurationSection(_ issue: AppModel.ConfigurationIssue) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                switch issue.kind {
                case .corruptRecovered:
                    Text("The saved configuration was unreadable. A backup was kept and defaults are in use.")
                    if let detail = issue.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                case .unsupportedVersion:
                    Text("This configuration was written by a newer version. Saving is disabled so the file is not overwritten.")
                    if let detail = issue.detail {
                        Text("schemaVersion \(detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .writeFailed:
                    Text("The configuration could not be saved. Changes apply until you quit.")
                }

                Button("Archive and Reset Configuration", role: .destructive) {
                    model.resetUnreadableConfiguration()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("Configuration", systemImage: "exclamationmark.triangle")
        }
    }

    private var logSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent events")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    Button {
                        Task {
                            isExporting = true
                            await model.exportDiagnostics()
                            isExporting = false
                            await reload()
                        }
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(isExporting)
                }

                if entries.isEmpty {
                    Text("No events recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.date, format: .dateTime.hour().minute().second())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 66, alignment: .leading)
                                Text(categoryName(entry.category))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 74, alignment: .leading)
                                Text(entry.message)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Text("Diagnostics stay on this Mac. Bluetooth addresses and home paths are removed before they are written.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("Log", systemImage: "list.bullet.rectangle")
        }
    }

    private func row(_ label: LocalizedStringResource, _ value: LocalizedStringResource) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func deviceDetail(_ device: DeviceState) -> String {
        DiagnosticsPresentation.deviceDetail(for: device)
    }

    private var systemPowerText: LocalizedStringResource {
        switch model.engineState.system.power {
        case .awake: "Awake"
        case .goingToSleep: "Going to sleep"
        case .asleep: "Asleep"
        case .unknown: "Unknown"
        }
    }

    private var displayText: LocalizedStringResource {
        switch model.engineState.system.display {
        case .awake: "Awake"
        case .asleep: "Asleep"
        case .unknown: "Unknown"
        }
    }

    private var sessionText: LocalizedStringResource {
        switch model.engineState.system.session {
        case .active: "Active"
        case .inactive: "Inactive"
        case .unknown: "Unknown"
        }
    }

    private var bluetoothText: LocalizedStringResource {
        switch model.engineState.system.bluetooth {
        case .available: "Available"
        case .unavailable: "Off"
        case .unauthorized: "Access denied"
        case .unknown: "Unknown"
        }
    }

    private func categoryName(_ category: DiagnosticsCategory) -> LocalizedStringResource {
        switch category {
        case .system: "System"
        case .bluetooth: "Bluetooth"
        case .coordinator: "Coordinator"
        case .audio: "Audio"
        case .update: "Update"
        case .configuration: "Configuration"
        }
    }

    private func reload() async {
        entries = model.diagnostics.recent(limit: 60)
    }
}
