import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DevicesSettingsView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
            DiagnosticsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 470)
        .blueLinkWindowFrosting()
        .background(SettingsWindowAccessor())
        .task { model.refresh() }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.configuration.isGloballyEnabled },
                    set: { model.setGlobalEnabled($0) }
                )) {
                    Text("Manage connections automatically")
                    Text("Connect and disconnect the devices below with the display and system sleep. Turning this off never disconnects a device.")
                }

                LabeledContent("Managed devices") {
                    Text("\(model.engineState.managedDeviceCount)")
                        .monospacedDigit()
                }
                LabeledContent("Connected now") {
                    Text("\(model.engineState.connectedCount)")
                        .monospacedDigit()
                }
            } header: {
                Text("Management")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { model.loginStatus == .enabled },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Text("Launch at login")
                    Text("Uses the system login item. BlueLink never installs a background service.")
                }

                switch model.loginStatus {
                case .requiresApproval:
                    LabeledContent("Approval required in System Settings → General → Login Items.") {
                        Button("Open Login Items") {
                            model.openLoginItemsSettings()
                        }
                    }
                case .notFound:
                    Text("Login items require the app to run from a signed application bundle.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                default:
                    EmptyView()
                }

                if let loginError = model.loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Check for Updates")
                        Text(model.isUpdateCheckConfigured
                             ? LocalizedStringKey("Checks GitHub Releases. Nothing is downloaded or installed automatically.")
                             : LocalizedStringKey("Update checks stay off until a release repository is configured."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.isCheckingForUpdates ? LocalizedStringKey("Checking…") : LocalizedStringKey("Check Now")) {
                        Task { await model.checkForUpdates() }
                    }
                    .disabled(model.isCheckingForUpdates || !model.isUpdateCheckConfigured)
                }

                if let message = model.updateMessage {
                    HStack {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.availableUpdate != nil {
                            Button("Open Release Page") {
                                model.openUpdatePage()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Updates")
            }

            Section {
                Text("BlueLink asks for Bluetooth access the first time it reads your paired devices. It never powers Bluetooth on, never pairs or unpairs devices, and never manages a device you have not selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
