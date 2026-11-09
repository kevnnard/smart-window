import AppKit
import ApplicationServices
import AVFoundation
import CoreAudio
import Darwin
import Foundation

/// Feeds the Call HUD: which call apps are capturing the microphone, and the mic level while a call
/// is live.
///
/// Detection reads CoreAudio's process objects (macOS 14 or later) twice a second, off the main
/// thread: each process's PID, bundle ID and whether it is running input. It needs no permission
/// and never opens the microphone. On macOS 13 there are no process objects, so there is no call HUD.
///
/// A browser call is named after the service in the browser window title (Meet, Teams, Zoom…),
/// read with the Accessibility permission SmartWindow already has; without it the browser is shown.
///
/// The level meter opens the microphone in SmartWindow itself, so it runs only during a live call and
/// only once the Microphone permission was granted in Settings → Permissions; it never asks on its
/// own. While it runs, macOS also lists SmartWindow as using the microphone.
@MainActor
final class CallMonitorService {
    static let pollInterval: TimeInterval = 0.5

    private let state: CallHUDState
    private let readQueue = DispatchQueue(label: "SmartWindow.CallMonitor", qos: .utility)
    private var tracker = CallTracker()
    private var resolver = WebCallServiceResolver()
    private var timer: Timer?
    private var reading = false
    private let meter = MicLevelMeter()

    init(state: CallHUDState? = nil) {
        self.state = state ?? .shared
    }

    func start() {
        guard timer == nil, AudioProcessReader.isSupported else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard !reading else { return }
        reading = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let tracked = tracker.session.flatMap { $0.endedAt == nil ? $0.app : nil }
        readQueue.async { [weak self] in
            let active = CallAppCatalog.activeCalls(in: AudioProcessReader.read(), excluding: ownPID)
            // Only while a browser holds the mic: the window titles of the browser with the call.
            let source = Self.titleSource(tracked: tracked, active: active)
            let service = source.flatMap { WebCallService.match(windowTitles: BrowserWindowTitles.read(bundleID: $0.bundleID)) }
            Task { @MainActor in self?.apply(active, source: source, service: service) }
        }
    }

    /// Whose window titles name the call: the app the call is (or is about to be) on, the same one
    /// CallTracker picks — the tracked app while it holds input, else the first active app — and
    /// only when it is a browser. A native call reads no titles.
    nonisolated static func titleSource(tracked: CallApp?, active: [CallApp]) -> CallApp? {
        let app = tracked.flatMap { active.contains($0) ? $0 : nil } ?? active.first
        return app?.isBrowser == true ? app : nil
    }

    private func apply(_ active: [CallApp], source: CallApp?, service matched: WebCallService?) {
        reading = false
        let change = tracker.update(active: active, at: Date())
        // Every live session goes through the resolver, native ones too, so a hop to a native app
        // forgets the browser's service.
        let service = tracker.session.flatMap { session in
            session.endedAt == nil
                ? resolver.resolve(confirmedAt: session.confirmedAt, app: session.app,
                                   matched: source == session.app ? matched : nil)
                : state.presentation?.service
        }
        if change != nil || tracker.session != state.presentation?.session || service != state.presentation?.service {
            state.update(session: tracker.session, service: service)
        }
        let live = tracker.session.map { $0.endedAt == nil } ?? false
        if live, MicrophoneAccess.status() == .granted {
            meter.start()
        } else {
            meter.stop()
        }
    }
}

/// Titles of a browser's windows, front first, through Accessibility. Empty without the permission.
enum BrowserWindowTitles {
    static func read(bundleID: String) -> [String] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // A busy browser must not stall the poll.
        AXUIElementSetMessagingTimeout(element, 0.2)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return [] }
        return list.prefix(12).compactMap { window in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
            return title as? String
        }
    }
}

/// Reads CoreAudio's process objects.
enum AudioProcessReader {
    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    static func read() -> [AudioInputProcess] {
        guard #available(macOS 14.0, *) else { return [] }
        return processObjects().compactMap(process)
    }

    @available(macOS 14.0, *)
    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        // The list can shrink between the two calls: keep only what was written.
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    @available(macOS 14.0, *)
    private static func process(_ object: AudioObjectID) -> AudioInputProcess? {
        guard let pid: pid_t = value(object, kAudioProcessPropertyPID) else { return nil }
        let running: UInt32 = value(object, kAudioProcessPropertyIsRunningInput) ?? 0
        return AudioInputProcess(pid: pid, bundleID: bundleID(object), executable: executableName(pid),
                                 isRunningInput: running != 0)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr,
              size == UInt32(MemoryLayout<T>.size) else { return nil }
        return pointer.pointee
    }

    @available(macOS 14.0, *)
    private static func bundleID(_ object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              size == UInt32(MemoryLayout<CFString?>.size),
              let string = value?.takeRetainedValue() as String?, !string.isEmpty else { return nil }
        return string
    }

    /// Daemons such as avconferenced have no bundle ID.
    private static func executableName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Microphone permission. Reading it is safe without a usage description; asking is not, so a
/// debug build without Info.plist cannot ask.
enum MicrophoneAccess {
    static let usageKey = "NSMicrophoneUsageDescription"

    static func status() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .unknown
        }
    }

    static var canAsk: Bool { Bundle.main.object(forInfoDictionaryKey: usageKey) != nil }
}

/// Measures the default input's level with an audio engine tap and publishes it about 20 times a second.
@MainActor
final class MicLevelMeter {
    private let state: MicLevelState
    private var engine: AVAudioEngine?
    /// The engine failed to start in this call; it is not retried until the call ends.
    private var failed = false
    /// Bumped on every start and stop, so a level queued by a stopped engine is dropped.
    private var generation = 0

    init(state: MicLevelState? = nil) {
        self.state = state ?? .shared
    }

    func start() {
        guard engine == nil, !failed else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            failed = true
            return
        }
        generation += 1
        let current = generation
        var lastPublish = Date.distantPast
        var smoothed = 0.0
        // About 50 ms per buffer at the input's own rate.
        let bufferSize = AVAudioFrameCount(format.sampleRate / 20)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let level = MicLevel.normalized(rms: (sum / Float(count)).squareRoot())
            // Rises fast, falls slower, like a level meter.
            smoothed = level > smoothed ? level : smoothed * 0.7 + level * 0.3
            let now = Date()
            guard now.timeIntervalSince(lastPublish) >= 0.045 else { return }
            lastPublish = now
            let value = smoothed
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.state.level = value
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            failed = true
            return
        }
        self.engine = engine
        state.isMetering = true
    }

    func stop() {
        failed = false
        guard let engine else { return }
        generation += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        state.isMetering = false
        state.level = 0
    }
}
