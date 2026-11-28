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
        .frame(width: 580, height: 560)
        .blueLinkWindowFrosting()
        .background(SettingsWindowAccessor())
        .task { model.refresh() }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var automaticChecksForUpdates = false
    @State private var automaticallyDownloadsUpdates = false

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
                if MacSparkleUpdaterController.shared.isConfigured {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Check for Updates")
                            Text("Uses the signed GitHub update feed. No account or telemetry is sent.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check for Updates…") {
                            MacSparkleUpdaterController.shared.checkForUpdates()
                        }
                    }

                    Toggle(isOn: $automaticChecksForUpdates) {
                        Text("Check for updates automatically")
                        Text("Checks the signed feed at most once a day while BlueLink is running.")
                    }
                    .onChange(of: automaticChecksForUpdates) { _, isEnabled in
                        MacSparkleUpdaterController.shared.updater?.automaticallyChecksForUpdates = isEnabled
                        if !isEnabled {
                            automaticallyDownloadsUpdates = false
                            MacSparkleUpdaterController.shared.updater?.automaticallyDownloadsUpdates = false
                        }
                    }

                    Toggle(isOn: $automaticallyDownloadsUpdates) {
                        Text("Automatically download updates")
                        Text("Sparkle downloads the signed update in the background and asks before installing it when BlueLink quits.")
                    }
                    .disabled(!automaticChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, isEnabled in
                        MacSparkleUpdaterController.shared.updater?.automaticallyDownloadsUpdates = isEnabled
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Check for Updates")
                            Text(model.isUpdateCheckConfigured
                                 ? LocalizedStringKey("This build has no Sparkle update key. It can check GitHub Releases only.")
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
        .onAppear {
            guard let updater = MacSparkleUpdaterController.shared.updater else { return }
            automaticChecksForUpdates = updater.automaticallyChecksForUpdates
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        }
    }
}
