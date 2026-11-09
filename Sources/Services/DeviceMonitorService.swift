import AppKit
import CoreAudio
import IOBluetooth
import IOKit

/// Feeds the notch with Bluetooth and USB devices connecting, disconnecting or running low.
///
/// A snapshot merges two reads, both off the main thread:
/// - Bluetooth: `system_profiler SPBluetoothDataType -json` (about 0.1 s, killed after 5 s). It is
///   a source of AirPods' left, right and case levels; its output keys are undocumented.
/// - HID: the IORegistry's `IOHIDDevice` and `AppleDeviceManagementHIDEventService` entries, read
///   in-process for the keys the parser uses (BatteryPercent for Magic devices, USB devices).
///
/// Snapshots are taken after a change notification, debounced: IOKit HID matching and termination
/// (USB and Bluetooth keyboards, mice, trackpads, controllers), the CoreAudio device list
/// (headphones), wake from sleep, and IOBluetooth connect and disconnect notifications when the
/// Bluetooth permission is granted. A slow poll catches battery drops and anything else.
@MainActor
final class DeviceMonitorService: NSObject {
    private let state: SystemHUDState
    private lazy var engine = DeviceMonitorEngine(
        snapshot: DeviceSnapshotReader.read,
        schedule: DeviceMonitorTimer.runLoop,
        publish: { [weak self] event in self?.state.show(SystemHUDEvent(device: event)) })
    private var notificationPort: IONotificationPortRef?
    private var hidIterators: [io_iterator_t] = []
    private var audioDevicesListener: AudioObjectPropertyListenerBlock?
    private var wakeObserver: NSObjectProtocol?
    private var bluetoothConnect: IOBluetoothUserNotification?
    private var permissionCheck: Timer?

    init(state: SystemHUDState? = nil) {
        self.state = state ?? .shared
        super.init()
    }

    func start() {
        guard notificationPort == nil else { return }
        engine.start()
        watchHIDDevices()
        watchAudioDevices()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engine.trigger() }
        }
        startBluetoothNotificationsIfAllowed()
        // The permission may be granted later in Settings; checking it is cheap.
        let timer = Timer(timeInterval: DeviceMonitorPolicy.batteryPoll, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.startBluetoothNotificationsIfAllowed() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        permissionCheck = timer
    }

    // MARK: - HID

    private func watchHIDDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                           .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            DeviceMonitorService.drain(iterator)
            guard let context else { return }
            let service = Unmanaged<DeviceMonitorService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.engine.trigger() }
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            guard IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOHIDDevice"), callback, context,
                                                   &iterator) == KERN_SUCCESS else { continue }
            // Draining arms the notification; the devices already there are the launch snapshot.
            Self.drain(iterator)
            hidIterators.append(iterator)
        }
    }

    nonisolated private static func drain(_ iterator: io_iterator_t) {
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            IOObjectRelease(entry)
        }
    }

    // MARK: - Audio

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Bluetooth headphones add an audio device when they connect, with or without the permission.
    private func watchAudioDevices() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.engine.trigger() }
        }
        var address = Self.devicesAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            audioDevicesListener = block
        }
    }

    // MARK: - Bluetooth

    /// Only with the permission granted: IOBluetooth without it shows the prompt, and without the
    /// usage description (a debug build) terminates the app.
    private func startBluetoothNotificationsIfAllowed() {
        guard bluetoothConnect == nil, BluetoothAccess.status() == .granted else { return }
        bluetoothConnect = IOBluetoothDevice.register(forConnectNotifications: self,
                                                      selector: #selector(bluetoothConnected(_:device:)))
    }

    /// Also called once per device already connected when the notification is registered.
    @objc nonisolated private func bluetoothConnected(_ notification: IOBluetoothUserNotification,
                                                      device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(bluetoothDisconnected(_:device:)))
        Task { @MainActor in self.engine.trigger() }
    }

    @objc nonisolated private func bluetoothDisconnected(_ notification: IOBluetoothUserNotification,
                                                         device: IOBluetoothDevice) {
        notification.unregister()
        Task { @MainActor in self.engine.trigger() }
    }
}

/// Timing of the device monitor and which HID services are devices, apart from timers and IOKit.
enum DeviceMonitorPolicy {
    /// Notifications come in bursts (one per HID interface, audio and Bluetooth for one device).
    static let debounce: TimeInterval = 0.75
    /// Battery levels change slowly; this only needs to catch the 20 % and 10 % crossings.
    static let batteryPoll: TimeInterval = 60
    /// AirPods' levels appear a moment after they connect: reads before announcing them without one.
    static let lateBatteryRetries: [TimeInterval] = [1.5, 3]

    /// Transports of devices inside the Mac.
    private static let internalTransports: Set<String> = ["spi", "fifo", "i2c", "virtual"]
    /// Words in a product name that mark the Mac's own parts, hubs and software devices.
    private static let internalWords: Set<String> = ["internal", "hub", "t2", "ibridge", "virtual"]

    /// Whether a HID service is a device someone plugged in or paired (S1).
    static func isExternal(_ service: [String: Any]) -> Bool {
        if flag(service["Built-In"]) || flag(service["HIDVirtualDevice"]) { return false }
        let transport = (service["Transport"] as? String ?? "").lowercased()
        if internalTransports.contains(transport) { return false }
        let product = (service["Product"] as? String ?? "").lowercased()
        if product.contains("touch bar") { return false }
        let words = product.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // "VirtualHIDKeyboard" is one word.
        return !words.contains { internalWords.contains($0) || $0.hasPrefix("virtual") }
    }

    /// One device per external HID device, in first-seen order. A device has an entry per interface;
    /// the one with a battery gives the level, a standard one the kind.
    static func externalHIDDevices(fromRegistry services: [[String: Any]]) -> [DeviceInfo] {
        let devices = DeviceParsers.hidDevices(fromRegistry: services.filter(isExternal))
        var order: [String] = []
        var best: [String: DeviceInfo] = [:]
        for device in devices {
            guard let current = best[device.id] else {
                order.append(device.id)
                best[device.id] = device
                continue
            }
            var merged = current.kind == .generic && device.kind != .generic ? device : current
            if merged.batteries.isEmpty { merged.batteries = current.batteries.isEmpty ? device.batteries : current.batteries }
            best[device.id] = merged
        }
        return order.compactMap { best[$0] }
    }

    /// A new headphone without a battery level yet, worth reading again before announcing.
    static func awaitsBattery(_ snapshot: [DeviceInfo], known: Set<String>) -> Bool {
        snapshot.contains { device in
            !known.contains(device.id) && device.transport == .bluetooth
                && [.airpods, .headphones, .headset].contains(device.kind)
                && device.batteries.allSatisfy { $0.level == nil }
        }
    }

    /// CF booleans arrive as Bool, plists may say 1.
    private static func flag(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool: return value
        case let value as Int: return value != 0
        case let value as String: return ["yes", "true", "1"].contains(value.lowercased())
        default: return false
        }
    }
}

/// A scheduled action that can be called off.
final class DeviceMonitorTimer {
    private let onCancel: () -> Void

    init(cancel: @escaping () -> Void) {
        onCancel = cancel
    }

    func cancel() {
        onCancel()
    }

    /// A one-shot main run loop timer; common modes, so it also fires while a menu is open.
    static func runLoop(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> DeviceMonitorTimer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = delay * 0.1
        RunLoop.main.add(timer, forMode: .common)
        return DeviceMonitorTimer { timer.invalidate() }
    }
}

/// When to read the connected devices and what to announce. The snapshot and the timers are
/// injected, so the probe drives it with a fake clock.
@MainActor
final class DeviceMonitorEngine {
    typealias Snapshot = (@escaping @MainActor ([DeviceInfo]?) -> Void) -> Void
    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> DeviceMonitorTimer

    private let snapshot: Snapshot
    private let schedule: Schedule
    private let publish: @MainActor (DeviceEvent) -> Void
    private var tracker = DeviceChangeTracker()
    private var running = false
    private var hasBaseline = false
    /// Devices in the last snapshot given to the tracker.
    private var known: Set<String> = []
    private var reading = false
    /// Something changed while a read was running; that read may have missed it.
    private var changedDuringRead = false
    private var pending: DeviceMonitorTimer?
    private var poll: DeviceMonitorTimer?

    init(snapshot: @escaping Snapshot, schedule: @escaping Schedule,
         publish: @escaping @MainActor (DeviceEvent) -> Void) {
        self.snapshot = snapshot
        self.schedule = schedule
        self.publish = publish
    }

    /// Records what is connected without announcing it, then polls.
    func start() {
        guard !running else { return }
        running = true
        read(retry: 0)
        schedulePoll()
    }

    func stop() {
        running = false
        pending?.cancel()
        poll?.cancel()
        pending = nil
        poll = nil
    }

    /// Something may have connected or disconnected: read once things settle.
    func trigger() {
        guard running else { return }
        pending?.cancel()
        pending = schedule(DeviceMonitorPolicy.debounce) { [weak self] in
            self?.pending = nil
            self?.read(retry: 0)
        }
    }

    private func schedulePoll() {
        poll = schedule(DeviceMonitorPolicy.batteryPoll) { [weak self] in
            guard let self, self.running else { return }
            self.schedulePoll()
            // A read waiting for its turn or a retry already covers it.
            if self.pending == nil { self.read(retry: 0) }
        }
    }

    private func read(retry: Int) {
        guard running else { return }
        guard !reading else {
            changedDuringRead = true
            return
        }
        reading = true
        snapshot { [weak self] devices in
            guard let self else { return }
            self.reading = false
            guard self.running else { return }
            if self.changedDuringRead {
                self.changedDuringRead = false
                self.trigger()
                return
            }
            // Missing data means the reader failed, not that every device disconnected.
            // Keep the tracker baseline until the next notification or periodic read succeeds.
            guard let devices else { return }
            let retries = DeviceMonitorPolicy.lateBatteryRetries
            if self.hasBaseline, retry < retries.count, DeviceMonitorPolicy.awaitsBattery(devices, known: self.known) {
                self.pending = self.schedule(retries[retry]) { [weak self] in
                    self?.pending = nil
                    self?.read(retry: retry + 1)
                }
                return
            }
            self.hasBaseline = true
            self.known = Set(devices.map(\.id))
            for event in self.tracker.update(devices) {
                self.publish(event)
            }
        }
    }
}

/// Reads the connected devices on a background queue.
enum DeviceSnapshotReader {
    private static let queue = DispatchQueue(label: "com.smartwindow.devices", qos: .utility)
    /// The registry keys the HID parser and the filter use; reading only these skips the large ones.
    private static let registryKeys = [
        "Product", "Transport", "Built-In", "HIDVirtualDevice", "BatteryPercent", "BatteryStatusFlags",
        "BatteryIsCharging", "IsCharging",
        "DeviceAddress", "SerialNumber", "LocationID", "PrimaryUsagePage", "PrimaryUsage",
    ]

    static func read(_ completion: @escaping @MainActor ([DeviceInfo]?) -> Void) {
        queue.async {
            guard let data = systemProfilerBluetooth(),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["SPBluetoothDataType"] is [[String: Any]] else {
                Task { @MainActor in completion(nil) }
                return
            }
            let bluetooth = DeviceParsers.bluetoothDevices(fromSystemProfiler: data)
            let services = ["IOHIDDevice", "AppleDeviceManagementHIDEventService"].flatMap(registryServices)
            let devices = DeviceParsers.merge(bluetooth: bluetooth,
                                              hid: DeviceMonitorPolicy.externalHIDDevices(fromRegistry: services))
            Task { @MainActor in completion(devices) }
        }
    }

    /// `system_profiler SPBluetoothDataType -json`, or nil when it fails or takes too long.
    private static func systemProfilerBluetooth(timeout: TimeInterval = 5) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return process.terminationReason == .exit && process.terminationStatus == 0 ? data : nil
    }

    private static func registryServices(ofClass name: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var services: [[String: Any]] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var service: [String: Any] = [:]
            for key in registryKeys {
                if let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() {
                    service[key] = value
                }
            }
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS {
                service["IORegistryEntryID"] = Int(truncatingIfNeeded: entryID)
            }
            services.append(service)
        }
        return services
    }
}
