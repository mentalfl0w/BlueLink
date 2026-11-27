import Foundation
import CoreAudio
import BlueLinkCore

public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var isBluetooth: Bool
    public var transportType: UInt32

    public init(id: String, name: String, isBluetooth: Bool, transportType: UInt32) {
        self.id = id
        self.name = name
        self.isBluetooth = isBluetooth
        self.transportType = transportType
    }
}

/// CoreAudio HAL adapter. Only output routing is exposed; input, volume and
/// sample rates are never modified.
public struct AudioRouteController: Sendable {
    private let listenerQueue: DispatchQueue

    public init(listenerQueue: DispatchQueue = DispatchQueue(label: "dev.bluelink.audio")) {
        self.listenerQueue = listenerQueue
    }

    public func outputDevices() -> [AudioOutputDevice] {
        Self.allOutputDevices()
    }

    /// Sets the default output once, waiting a bounded time for the device to
    /// appear after the ACL link is up. Returns false when the UID never shows
    /// up; the caller reports that separately and must not reconnect Bluetooth.
    public func route(uid: String, timeout: Duration) async -> Bool {
        if let device = Self.deviceID(forUID: uid) {
            return Self.setDefaultOutput(device)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            continuation.yield(())
        }
        let addStatus = AudioObjectAddPropertyListenerBlock(systemObject, &address, listenerQueue, listener)
        guard addStatus == noErr else { return false }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }

        for await _ in stream {
            if let device = Self.deviceID(forUID: uid) {
                timeoutTask.cancel()
                AudioObjectRemovePropertyListenerBlock(systemObject, &address, listenerQueue, listener)
                return Self.setDefaultOutput(device)
            }
        }
        timeoutTask.cancel()
        AudioObjectRemovePropertyListenerBlock(systemObject, &address, listenerQueue, listener)
        return false
    }

    // MARK: - HAL queries

    static func allOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }

        return devices.compactMap { device -> AudioOutputDevice? in
            guard outputChannelCount(device) > 0,
                  let uid = stringProperty(device, selector: kAudioDevicePropertyDeviceUID),
                  !uid.isEmpty else { return nil }
            let name = stringProperty(device, selector: kAudioObjectPropertyName) ?? uid
            let transport = uint32Property(device, selector: kAudioDevicePropertyTransportType) ?? 0
            let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
            return AudioOutputDevice(id: uid, name: name, isBluetooth: isBluetooth, transportType: transport)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        resolve(uid: uid)
    }

    private static func resolve(uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &devices) == noErr else {
            return nil
        }
        return devices.first { device in
            outputChannelCount(device) > 0
                && stringProperty(device, selector: kAudioDevicePropertyDeviceUID) == uid
        }
    }

    static func setDefaultOutput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDevice = device
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDevice
        )
        return status == noErr
    }

    private static func outputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(into: 0) { total, buffer in
            total += Int(buffer.mNumberChannels)
        }
    }

    private static func stringProperty(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32Property(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
