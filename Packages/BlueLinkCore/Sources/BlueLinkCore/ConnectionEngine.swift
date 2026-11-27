import Foundation

/// Event-driven connection coordinator.
///
/// All policy decisions happen here; the platform only reports observations
/// and executes transport calls. Events are queued and processed one at a time
/// so a slow Bluetooth call can never interleave two reconciliations.
public actor ConnectionEngine {
    private struct Runtime {
        var observed: ObservedConnection = .unknown
        var operation: OperationPhase = .idle
        var desired: DesiredConnection = .unmanaged
        var failure: DeviceFailure?
        var retryAttempt = 0
        var retryExhausted = false
        var generation = 0
        var manualDisconnectInCycle = false
        var suppressReconnect = false
        /// True from the moment a connection is observed until this app asks
        /// for a disconnect. A drop while true is an unexpected disconnect even
        /// if no automatic connection policy is currently driving the device.
        var expectsConnection = false
        /// A user asked for a disconnect while an operation was in flight.
        /// It is executed as soon as the connection state is observable.
        var pendingManualDisconnect = false
        var pendingRetry: Task<Void, Never>?
        var audioReady: Bool?
        var lastTransition: ObservedTransition = .none
        /// Timestamps of unexpected drops, used to cap a flapping reconnect loop.
        var unexpectedDropDates: [Date] = []
    }

    private nonisolated let transport: any BluetoothTransport
    private nonisolated let clock: any EngineClock
    private nonisolated let retryPolicy: RetryPolicy
    private nonisolated let connectTimeout: Duration
    private nonisolated let disconnectTimeout: Duration
    private nonisolated let randomUnit: @Sendable () -> Double

    public nonisolated let updates: AsyncStream<EngineState>
    public nonisolated let effects: AsyncStream<EngineEffect>

    private let stateContinuation: AsyncStream<EngineState>.Continuation
    private let effectContinuation: AsyncStream<EngineEffect>.Continuation

    private var configuration: AppConfiguration
    private var system: SystemSnapshot
    private var runtimes: [DeviceID: Runtime] = [:]
    private var pendingEvents: [EngineEvent] = []
    private var isProcessing = false
    private var lastEmitted: EngineState?
    private var wakeCycle = 0

    public init(
        configuration: AppConfiguration,
        system: SystemSnapshot,
        transport: any BluetoothTransport,
        clock: any EngineClock = SystemClock(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        connectTimeout: Duration = .seconds(25),
        disconnectTimeout: Duration = .seconds(10),
        randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        let sanitized = ConfigurationCoder.sanitize(configuration)
        self.configuration = sanitized
        self.system = system
        self.transport = transport
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.connectTimeout = connectTimeout
        self.disconnectTimeout = disconnectTimeout
        self.randomUnit = randomUnit

        let (stateStream, stateContinuation) = AsyncStream.makeStream(of: EngineState.self)
        let (effectStream, effectContinuation) = AsyncStream.makeStream(of: EngineEffect.self)
        updates = stateStream
        effects = effectStream
        self.stateContinuation = stateContinuation
        self.effectContinuation = effectContinuation

        for device in sanitized.devices {
            runtimes[device.id] = Runtime()
        }
    }

    // MARK: - Event intake

    public func send(_ event: EngineEvent) async {
        pendingEvents.append(event)
        guard !isProcessing else { return }
        isProcessing = true
        while !pendingEvents.isEmpty {
            let next = pendingEvents.removeFirst()
            await handle(next)
        }
        isProcessing = false
    }

    public func snapshot() -> EngineState {
        makeState()
    }

    // MARK: - Event handling

    private func handle(_ event: EngineEvent) async {
        switch event {
        case .start:
            await refreshAllObservations()
            reconcile(trigger: .launch)
            emit()

        case .systemChanged(let snapshot):
            let previous = system
            system = snapshot
            let becameAwake = previous.display == .asleep
                && snapshot.display == .awake
                && snapshot.power == .awake
                && previous.power != .asleep
            let displaySlept = previous.display == .awake && snapshot.display != .awake
            let powerSleeping = snapshot.power == .goingToSleep || snapshot.power == .asleep
            let bluetoothRecovered = previous.bluetooth != .available && snapshot.bluetooth == .available

            if displaySlept || powerSleeping {
                // Know what is actually connected before deciding to close it.
                await refreshAllObservations()
            }

            if becameAwake {
                wakeCycle &+= 1
                for id in runtimes.keys {
                    runtimes[id]?.manualDisconnectInCycle = false
                    runtimes[id]?.suppressReconnect = false
                    runtimes[id]?.audioReady = nil
                    resetBudget(id)
                }
                reconcile(trigger: .wakeCycle)
            } else if bluetoothRecovered {
                // The controller came back after launch or a manual power cycle.
                // This is a fresh budget, not a duplicate wake notification.
                for id in runtimes.keys { resetBudget(id) }
                reconcile(trigger: .bluetoothRecovered)
            } else {
                if !system.permitsAutomaticConnection {
                    for id in runtimes.keys { cancelRetry(id) }
                }
                reconcile(trigger: .none)
            }
            emit()

        case .externalDeviceChange(let id):
            guard runtimes[id] != nil else { return }
            let observed = await queryObserved(id)
            let trigger = applyObservation(id, observed)
            if trigger == .unexpectedDisconnect {
                await recordUnexpectedDisconnect(id)
            }
            reconcile(trigger: trigger)
            emit()

        case .observation(let id, let observed):
            let trigger = applyObservation(id, observed)
            if trigger == .unexpectedDisconnect {
                await recordUnexpectedDisconnect(id)
            }
            reconcile(trigger: trigger)
            emit()

        case .configurationChanged(let newConfiguration):
            configuration = ConfigurationCoder.sanitize(newConfiguration)
            synchronizeRuntimes()
            for id in runtimes.keys {
                resetBudget(id)
            }
            await refreshAllObservations()
            reconcile(trigger: .configurationChange)
            emit()

        case .manualConnect(let id):
            requestManualConnect(id)

        case .manualDisconnect(let id):
            requestManualDisconnect(id)

        case .retryNow(let id):
            guard configuration.device(id) != nil else { return }
            resetBudget(id)
            requestManualConnect(id)

        case .audioReadiness(let id, let ready):
            runtimes[id]?.audioReady = ready
            emit()

        case .retryDue(let id, let generation):
            handleRetryDue(id, generation: generation)
        }
    }

    // MARK: - Observations

    private func queryObserved(_ id: DeviceID) async -> ObservedConnection {
        do {
            return try await transport.isConnected(id) ? .connected : .disconnected
        } catch BluetoothTransportError.deviceNotFound {
            return .unavailable
        } catch {
            return .unknown
        }
    }

    private func refreshAllObservations() async {
        for device in configuration.devices {
            let observed = await queryObserved(device.id)
            _ = applyObservation(device.id, observed)
        }
    }

    @discardableResult
    private func applyObservation(_ id: DeviceID, _ observed: ObservedConnection) -> ReconcileTrigger {
        guard var runtime = runtimes[id] else { return .none }
        let previous = runtime.observed
        runtime.observed = observed
        runtime.lastTransition = .none

        if previous != .connected, observed == .connected {
            runtime.lastTransition = .becameConnected
            runtime.expectsConnection = true
            runtime.failure = nil
            runtime.retryAttempt = 0
            runtime.retryExhausted = false
            runtime.suppressReconnect = false
        } else if previous == .connected, observed != .connected {
            runtime.lastTransition = .becameDisconnected
            if runtime.expectsConnection,
               runtime.operation == .idle,
               !runtime.suppressReconnect {
                runtime.expectsConnection = false
                runtimes[id] = runtime
                return .unexpectedDisconnect
            }
        }
        runtimes[id] = runtime
        return .none
    }

    // MARK: - Manual control

    private func requestManualConnect(_ id: DeviceID) {
        guard configuration.device(id) != nil, var runtime = runtimes[id] else { return }
        guard system.session == .active else {
            runtime.failure = makeFailure(.sessionInactive)
            runtimes[id] = runtime
            emit()
            return
        }
        guard system.bluetooth == .available else {
            let kind: DeviceFailure.Kind = system.bluetooth == .unauthorized ? .unauthorized : .bluetoothUnavailable
            runtime.failure = makeFailure(kind)
            runtimes[id] = runtime
            emit()
            return
        }
        runtime.manualDisconnectInCycle = false
        runtime.suppressReconnect = false
        runtime.retryExhausted = false
        runtimes[id] = runtime
        startConnect(id)
    }

    private func requestManualDisconnect(_ id: DeviceID) {
        guard configuration.device(id) != nil, var runtime = runtimes[id] else { return }
        runtime.manualDisconnectInCycle = system.display == .awake
        runtime.desired = .disconnected
        runtime.suppressReconnect = true
        runtime.expectsConnection = false
        runtime.pendingManualDisconnect = true
        runtime.pendingRetry?.cancel()
        runtime.pendingRetry = nil
        runtime.retryExhausted = false
        if runtime.operation == .connecting {
            // Invalidate the completion's generation: the late result must be
            // observed, then the disconnect runs against the real state.
            runtime.generation &+= 1
        }
        runtimes[id] = runtime
        if runtime.operation == .idle {
            if runtime.observed == .connected {
                startDisconnect(id)
            } else {
                runtime.pendingManualDisconnect = false
                runtimes[id] = runtime
                emit()
            }
        } else {
            emit()
        }
    }

    // MARK: - Reconciliation

    private func reconcile(trigger: ReconcileTrigger) {
        for device in configuration.devices {
            guard var runtime = runtimes[device.id] else { continue }

            if runtime.pendingManualDisconnect, runtime.operation == .idle {
                if runtime.observed == .connected {
                    startDisconnect(device.id)
                    continue
                }
                runtime.pendingManualDisconnect = false
                runtimes[device.id] = runtime
            }

            let input = PolicyInput(
                isGloballyEnabled: configuration.isGloballyEnabled,
                device: device,
                system: system,
                observed: runtime.observed,
                operation: runtime.operation,
                manualDisconnectInCurrentCycle: runtime.manualDisconnectInCycle,
                trigger: trigger
            )
            let decision = ConnectionPolicy.decide(input)

            switch decision {
            case .unmanaged:
                runtime.desired = .unmanaged
                if runtime.pendingRetry != nil {
                    runtime.pendingRetry?.cancel()
                    runtime.pendingRetry = nil
                }
                runtimes[device.id] = runtime

            case .preserve:
                runtimes[device.id] = runtime

            case .connect:
                runtime.desired = .connected
                runtimes[device.id] = runtime
                if runtime.observed != .connected,
                   runtime.operation == .idle,
                   !runtime.retryExhausted,
                   runtime.pendingRetry == nil {
                    startConnect(device.id)
                }

            case .disconnect:
                runtime.desired = .disconnected
                runtime.suppressReconnect = true
                if runtime.pendingRetry != nil {
                    runtime.pendingRetry?.cancel()
                    runtime.pendingRetry = nil
                }
                runtimes[device.id] = runtime
                if runtime.observed == .connected, runtime.operation == .idle {
                    startDisconnect(device.id)
                }
            }
        }
    }

    // MARK: - Operations

    private func startConnect(_ id: DeviceID) {
        guard var runtime = runtimes[id], runtime.operation == .idle else { return }
        runtime.generation &+= 1
        let generation = runtime.generation
        runtime.operation = .connecting
        runtime.desired = .connected
        runtime.suppressReconnect = false
        runtime.pendingRetry?.cancel()
        runtime.pendingRetry = nil
        runtimes[id] = runtime
        emit()
        Task { await self.performConnect(id, generation: generation) }
    }

    private func startDisconnect(_ id: DeviceID) {
        guard var runtime = runtimes[id], runtime.operation == .idle else { return }
        runtime.generation &+= 1
        let generation = runtime.generation
        runtime.operation = .disconnecting
        runtime.desired = .disconnected
        runtime.suppressReconnect = true
        runtime.expectsConnection = false
        runtime.pendingManualDisconnect = false
        runtimes[id] = runtime
        emit()
        Task { await self.performDisconnect(id, generation: generation) }
    }

    private func performConnect(_ id: DeviceID, generation: Int) async {
        let started = await clock.now()
        do {
            try await transport.connect(id, timeout: connectTimeout)
            let observed = await queryObserved(id)
            let elapsed = (await clock.now()).timeIntervalSince(started)
            let timedOut = elapsed > connectTimeout.seconds
            await finishConnect(
                id,
                generation: generation,
                succeeded: observed == .connected,
                observed: observed,
                failure: timedOut ? makeFailure(.timedOut) : nil
            )
        } catch {
            let observed = await queryObserved(id)
            await finishConnect(
                id,
                generation: generation,
                succeeded: observed == .connected,
                observed: observed,
                failure: mapFailure(error)
            )
        }
    }

    private func finishConnect(
        _ id: DeviceID,
        generation: Int,
        succeeded: Bool,
        observed: ObservedConnection,
        failure: DeviceFailure?
    ) async {
        guard var runtime = runtimes[id] else { return }
        let isCurrent = runtime.generation == generation
        runtime.operation = .idle
        runtime.observed = observed

        if !isCurrent {
            // The intent changed while the system call was running. Never
            // discard the observation: reconcile against the newest intent.
            runtimes[id] = runtime
            emit()
            if runtime.pendingManualDisconnect, observed == .connected {
                startDisconnect(id)
            } else {
                reconcile(trigger: .none)
            }
            return
        }

        if succeeded {
            runtime.failure = nil
            runtime.retryAttempt = 0
            runtime.retryExhausted = false
            runtime.suppressReconnect = false
            runtime.expectsConnection = true
            if let uid = configuration.device(id)?.policy.preferredAudioUID {
                effectContinuation.yield(.routeAudio(device: id, uid: uid))
            }
            runtimes[id] = runtime
            emit()
            // The system call outlived a policy change (for example display
            // sleep). Re-evaluate now that the connection is observable.
            reconcile(trigger: .none)
            return
        }

        runtime.failure = failure ?? makeFailure(.connectFailed)
        runtime.retryAttempt += 1
        runtimes[id] = runtime
        emit()

        scheduleRetryIfNeeded(id)
    }

    private func performDisconnect(_ id: DeviceID, generation: Int) async {
        do {
            try await transport.disconnect(id, timeout: disconnectTimeout)
            let observed = await queryObserved(id)
            await finishDisconnect(id, generation: generation, observed: observed, failure: nil)
        } catch {
            let observed = await queryObserved(id)
            await finishDisconnect(id, generation: generation, observed: observed, failure: mapFailure(error))
        }
    }

    private func finishDisconnect(
        _ id: DeviceID,
        generation: Int,
        observed: ObservedConnection,
        failure: DeviceFailure?
    ) async {
        guard var runtime = runtimes[id] else { return }
        let isCurrent = runtime.generation == generation
        runtime.operation = .idle
        runtime.observed = observed

        if !isCurrent {
            runtimes[id] = runtime
            emit()
            reconcile(trigger: .none)
            return
        }

        if observed == .connected {
            runtime.failure = failure ?? self.makeFailure(.disconnectFailed)
        } else {
            runtime.failure = failure
        }
        runtimes[id] = runtime
        emit()
        reconcile(trigger: .none)
        startDesiredConnectIfPossible(id)
    }

    /// A wake may have set `.connected` while a disconnect was still in flight.
    /// `reconcile(.none)` preserves that intent but never starts new work, so
    /// resume it once the operation becomes idle.
    private func startDesiredConnectIfPossible(_ id: DeviceID) {
        guard let runtime = runtimes[id],
              runtime.desired == .connected,
              runtime.operation == .idle,
              runtime.observed != .connected,
              !runtime.retryExhausted,
              !runtime.manualDisconnectInCycle,
              runtime.pendingRetry == nil,
              configuration.isGloballyEnabled,
              let device = configuration.device(id),
              !device.isPaused,
              system.permitsAutomaticConnection else { return }
        startConnect(id)
    }

    /// Caps a connect/drop loop that would otherwise retry forever without
    /// backoff. The cap clears only on a wake cycle, controller recovery,
    /// effective configuration change or explicit retry.
    private func recordUnexpectedDisconnect(_ id: DeviceID) async {
        guard var runtime = runtimes[id] else { return }
        let now = await clock.now()
        let windowStart = now.addingTimeInterval(-retryPolicy.unexpectedDropWindow.seconds)
        runtime.unexpectedDropDates.removeAll { $0 < windowStart }
        runtime.unexpectedDropDates.append(now)
        if runtime.unexpectedDropDates.count > retryPolicy.maximumUnexpectedDrops {
            runtime.retryExhausted = true
            runtime.failure = makeFailure(.reconnectRateLimited)
            runtime.pendingRetry?.cancel()
            runtime.pendingRetry = nil
        }
        runtimes[id] = runtime
    }

    private func scheduleRetryIfNeeded(_ id: DeviceID) {
        guard var runtime = runtimes[id],
              runtime.desired == .connected,
              runtime.operation == .idle,
              runtime.pendingRetry == nil else { return }

        guard runtime.retryAttempt < retryPolicy.maximumAttempts,
              let delay = retryPolicy.delay(
                  afterCompletedAttempts: runtime.retryAttempt,
                  randomUnit: randomUnit()
              ) else {
            runtime.retryExhausted = true
            runtimes[id] = runtime
            emit()
            return
        }

        let generation = runtime.generation
        let clock = self.clock
        runtime.pendingRetry = Task { [weak self] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            await self?.send(.retryDue(id, generation))
        }
        runtimes[id] = runtime
        emit()
    }

    private func handleRetryDue(_ id: DeviceID, generation: Int) {
        guard var runtime = runtimes[id],
              runtime.generation == generation,
              runtime.operation == .idle,
              runtime.desired == .connected else { return }
        runtime.pendingRetry = nil
        runtimes[id] = runtime
        guard system.permitsAutomaticConnection,
              !runtime.manualDisconnectInCycle,
              !runtime.retryExhausted else { return }
        startConnect(id)
    }

    // MARK: - Helpers

    private func resetBudget(_ id: DeviceID) {
        guard var runtime = runtimes[id] else { return }
        runtime.retryAttempt = 0
        runtime.retryExhausted = false
        runtime.unexpectedDropDates.removeAll()
        runtimes[id] = runtime
    }

    private func cancelRetry(_ id: DeviceID) {
        guard var runtime = runtimes[id] else { return }
        runtime.pendingRetry?.cancel()
        runtime.pendingRetry = nil
        runtimes[id] = runtime
    }

    private func synchronizeRuntimes() {
        let managed = Set(configuration.devices.map(\.id))
        for device in configuration.devices where runtimes[device.id] == nil {
            runtimes[device.id] = Runtime()
        }
        for id in runtimes.keys where !managed.contains(id) {
            runtimes[id]?.pendingRetry?.cancel()
            runtimes.removeValue(forKey: id)
        }
    }

    private func makeFailure(_ kind: DeviceFailure.Kind, detail: String? = nil) -> DeviceFailure {
        DeviceFailure(kind: kind, detail: detail, occurredAt: Date())
    }

    private func mapFailure(_ error: any Error) -> DeviceFailure {
        if let transportError = error as? BluetoothTransportError {
            switch transportError {
            case .deviceNotFound, .notPaired:
                return makeFailure(.deviceMissing)
            case .timedOut:
                return makeFailure(.timedOut)
            case .operationFailed(let code):
                return makeFailure(.connectFailed, detail: "IOReturn \(code)")
            case .busy, .unsupported:
                return makeFailure(.connectFailed)
            }
        }
        return makeFailure(.unknown)
    }

    private func makeState() -> EngineState {
        let devices = configuration.devices.compactMap { device -> DeviceState? in
            guard let runtime = runtimes[device.id] else { return nil }
            return DeviceState(
                id: device.id,
                name: device.cachedName,
                policy: device.policy,
                isPaused: device.isPaused,
                desired: runtime.desired,
                observed: runtime.observed,
                operation: runtime.operation,
                failure: runtime.failure,
                retryAttempt: runtime.retryAttempt,
                retryExhausted: runtime.retryExhausted,
                isManualOverrideActive: runtime.manualDisconnectInCycle,
                audioReady: runtime.audioReady
            )
        }
        return EngineState(
            system: system,
            isGloballyEnabled: configuration.isGloballyEnabled,
            devices: devices
        )
    }

    private func emit() {
        let state = makeState()
        guard state != lastEmitted else { return }
        lastEmitted = state
        stateContinuation.yield(state)
    }
}
