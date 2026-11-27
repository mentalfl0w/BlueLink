import Foundation
import Observation
import AppKit
import BlueLinkCore
import MacIntegration

/// Composition root for the app. Owns the engine, platform adapters and the
/// persisted configuration; views only call intents and read published state.
@MainActor
@Observable
final class AppModel {
    struct ConfigurationIssue: Equatable {
        enum Kind: Equatable {
            case corruptRecovered
            case unsupportedVersion
            case writeFailed
        }

        var kind: Kind
        var detail: String?
    }

    private(set) var configuration: AppConfiguration
    private(set) var engineState: EngineState
    private(set) var configurationIssue: ConfigurationIssue?
    private(set) var loginStatus: LoginItemController.Status = .unknown
    private(set) var loginError: String?
    private(set) var updateMessage: String?
    private(set) var availableUpdate: UpdateRelease?
    private(set) var isCheckingForUpdates = false
    private(set) var hasStarted = false

    var pairedDevices: [PairedDevice] = []
    var audioOutputs: [AudioOutputDevice] = []
    var isLoadingPairedDevices = false
    var showInputDevices = false

    private let transport: IOBluetoothTransport
    private let store: ConfigurationStore
    private let audio: AudioRouteController
    private let loginItem: LoginItemController
    private let updateChecker: UpdateChecker
    private let systemMonitor: SystemStateMonitor
    private let bluetoothMonitor: BluetoothEventMonitor
    let diagnostics: DiagnosticsLog

    private var engine: ConnectionEngine?
    private var tasks: [Task<Void, Never>] = []
    private var isSavingEnabled = true

    var isUpdateCheckConfigured: Bool { updateChecker.repository != nil }

    init() {
        let transport = IOBluetoothTransport()
        self.transport = transport
        store = .defaultStore()
        diagnostics = DiagnosticsLog()
        audio = AudioRouteController()
        loginItem = LoginItemController()
        let repository = Bundle.main.object(forInfoDictionaryKey: "BlueLinkUpdateRepository") as? String
        updateChecker = UpdateChecker(repository: repository)
        configuration = AppConfiguration()
        engineState = EngineState(system: .unknown, isGloballyEnabled: true, devices: [])
        systemMonitor = SystemStateMonitor(bluetoothReader: { [transport] in
            await transport.availability()
        })
        bluetoothMonitor = BluetoothEventMonitor()
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        loadConfiguration()

        let engine = ConnectionEngine(
            configuration: configuration,
            system: systemMonitor.current,
            transport: transport
        )
        self.engine = engine
        consume(engine)

        systemMonitor.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                await self?.send(.systemChanged(snapshot))
            }
        }
        systemMonitor.start()

        bluetoothMonitor.onDeviceActivity = { [weak self] id in
            Task { @MainActor in
                await self?.send(.externalDeviceChange(id))
            }
        }
        bluetoothMonitor.start()
        synchronizeMonitorRegistrations()

        Task { await engine.send(.start) }
        refreshLoginStatus()
        diagnostics.record(.system, String(localized: "app started"))
    }

    func stop() {
        hasStarted = false
        for task in tasks { task.cancel() }
        tasks.removeAll()
        systemMonitor.stop()
        bluetoothMonitor.stop()
        systemMonitor.onSnapshot = nil
        bluetoothMonitor.onDeviceActivity = nil
        engine = nil
    }

    /// One-shot refresh when the panel or settings opens. No timers.
    func refresh() {
        systemMonitor.refresh()
        refreshLoginStatus()
    }

    private func send(_ event: EngineEvent) async {
        await engine?.send(event)
    }

    private func consume(_ engine: ConnectionEngine) {
        let updates = engine.updates
        tasks.append(Task { @MainActor [weak self] in
            for await state in updates {
                guard let self else { return }
                self.engineState = state
            }
        })

        let effects = engine.effects
        tasks.append(Task { @MainActor [weak self] in
            for await effect in effects {
                guard let self else { return }
                switch effect {
                case .routeAudio(let device, let uid):
                    await self.routeAudio(device: device, uid: uid)
                }
            }
        })
    }

    private func routeAudio(device: DeviceID, uid: String) async {
        let success = await audio.route(uid: uid, timeout: .seconds(8))
        diagnostics.record(
            .audio,
            success ? String(localized: "preferred output applied") : String(localized: "preferred output unavailable")
        )
        await send(.audioReadiness(device, success))
    }

    // MARK: - Configuration

    private func loadConfiguration() {
        switch store.load() {
        case .loaded(let loaded):
            configuration = loaded
        case .missing:
            configuration = AppConfiguration()
            persist()
        case .corrupt:
            let backup = try? store.archiveCorruptFile()
            configuration = AppConfiguration()
            configurationIssue = ConfigurationIssue(
                kind: .corruptRecovered,
                detail: backup?.lastPathComponent
            )
            diagnostics.record(.configuration, String(localized: "corrupt configuration archived; defaults restored"))
            persist()
        case .unsupportedVersion(let version):
            configuration = AppConfiguration()
            isSavingEnabled = false
            configurationIssue = ConfigurationIssue(
                kind: .unsupportedVersion,
                detail: String(version)
            )
            diagnostics.record(.configuration, String(localized: "unsupported configuration version; saving disabled"))
        }
    }

    private func persist() {
        guard isSavingEnabled else { return }
        do {
            try store.save(configuration)
        } catch {
            configurationIssue = ConfigurationIssue(kind: .writeFailed, detail: nil)
            diagnostics.record(.configuration, String(localized: "configuration write failed"))
        }
    }

    private func updateConfiguration(_ mutate: (inout AppConfiguration) -> Void) {
        var next = configuration
        mutate(&next)
        configuration = ConfigurationCoder.sanitize(next)
        persist()
        synchronizeMonitorRegistrations()
        if let engine {
            let snapshot = configuration
            Task { await engine.send(.configurationChanged(snapshot)) }
        }
    }

    func setGlobalEnabled(_ enabled: Bool) {
        updateConfiguration { $0.isGloballyEnabled = enabled }
    }

    func setPaused(_ paused: Bool, for id: DeviceID) {
        guard var device = configuration.device(id) else { return }
        device.isPaused = paused
        updateConfiguration { $0.update(device) }
    }

    func updatePolicy(_ policy: DevicePolicy, for id: DeviceID) {
        guard var device = configuration.device(id) else { return }
        device.policy = policy
        updateConfiguration { $0.update(device) }
    }

    func addDevice(_ paired: PairedDevice) {
        guard configuration.device(paired.id) == nil else { return }
        let device = ManagedDevice(id: paired.id, cachedName: paired.name)
        updateConfiguration { $0.devices.append(device) }
        diagnostics.record(.configuration, String(localized: "device added"))
    }

    func removeDevice(_ id: DeviceID) {
        updateConfiguration { $0.devices.removeAll { $0.id == id } }
        diagnostics.record(.configuration, String(localized: "device removed"))
    }

    func resetUnreadableConfiguration() {
        guard configurationIssue?.kind == .unsupportedVersion || configurationIssue?.kind == .corruptRecovered else {
            return
        }
        _ = try? store.archiveCorruptFile()
        isSavingEnabled = true
        configuration = AppConfiguration()
        configurationIssue = nil
        persist()
        synchronizeMonitorRegistrations()
        if let engine {
            let snapshot = configuration
            Task { await engine.send(.configurationChanged(snapshot)) }
        }
        diagnostics.record(.configuration, String(localized: "configuration reset by user"))
    }

    private func synchronizeMonitorRegistrations() {
        bluetoothMonitor.setManagedDevices(configuration.devices.map(\.id))
    }

    // MARK: - Manual control

    func connect(_ id: DeviceID) {
        diagnostics.record(.bluetooth, String(localized: "manual connect requested"))
        Task { await send(.manualConnect(id)) }
    }

    func disconnect(_ id: DeviceID) {
        diagnostics.record(.bluetooth, String(localized: "manual disconnect requested"))
        Task { await send(.manualDisconnect(id)) }
    }

    func retry(_ id: DeviceID) {
        diagnostics.record(.bluetooth, String(localized: "explicit retry requested"))
        Task { await send(.retryNow(id)) }
    }

    // MARK: - Paired devices and audio

    func refreshPairedDevices() async {
        isLoadingPairedDevices = true
        defer { isLoadingPairedDevices = false }
        do {
            pairedDevices = try await transport.pairedDevices()
        } catch {
            pairedDevices = []
            diagnostics.record(.bluetooth, String(localized: "paired device query failed"))
        }
    }

    func refreshAudioOutputs() {
        audioOutputs = audio.outputDevices()
    }

    // MARK: - Login item

    func refreshLoginStatus() {
        loginStatus = loginItem.status()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            loginError = error.localizedDescription
            diagnostics.record(.system, String(localized: "login item change failed"))
        }
        refreshLoginStatus()
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    // MARK: - Updates

    func checkForUpdates() async {
        guard isUpdateCheckConfigured else {
            updateMessage = String(localized: "Update channel not configured")
            return
        }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let release = try await updateChecker.latestRelease(currentVersion: appVersion)
            availableUpdate = release
            updateMessage = release.map { String(localized: "Version \($0.version) is available") }
                ?? String(localized: "You're up to date")
            diagnostics.record(.update, release == nil ? String(localized: "no update available") : String(localized: "update available"))
        } catch {
            availableUpdate = nil
            updateMessage = String(localized: "Couldn't check for updates")
            diagnostics.record(.update, String(localized: "update check failed"))
        }
    }

    func openUpdatePage() {
        guard let availableUpdate else { return }
        NSWorkspace.shared.open(availableUpdate.pageURL)
    }

    // MARK: - Diagnostics

    var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }

    func exportDiagnostics() async {
        let header = """
        BlueLink \(appVersion) (\(buildNumber))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        exported \(ISO8601DateFormatter().string(from: Date()))
        """
        let text = diagnostics.exportText(header: header)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlueLink-Diagnostics.txt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            diagnostics.record(.system, String(localized: "diagnostics exported"))
        } catch {
            diagnostics.record(.system, String(localized: "diagnostics export failed"))
        }
    }
}
