import AppKit
import AudioToolbox
import CoreAudio

/// Feeds the notch Wings HUD: output volume and mute from CoreAudio listeners, and the built-in
/// display's brightness by polling. This only observes; the macOS HUD still appears.
@MainActor
final class SystemHUDService {
    private let state: SystemHUDState
    private var device: AudioDeviceID = kAudioObjectUnknown
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var lastVolume: SystemMonitorService.OutputVolume?
    private var brightnessTimer: Timer?
    private var brightnessDetector = BrightnessChangeDetector()

    init(state: SystemHUDState? = nil) {
        self.state = state ?? .shared
    }

    func start() {
        guard defaultDeviceListener == nil else { return }
        var address = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attachToDefaultDevice() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        defaultDeviceListener = block
        attachToDefaultDevice()

        // Brightness has no public change notification, and the brightness keys do not always reach
        // apps, so read it ten times a second; the call is cheap. Without a built-in display (lid
        // closed) each tick just finds nothing. Common modes: also polls while a menu is open.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollBrightness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
        #if DEBUG
        startDebugTrigger()
        #endif
    }

    #if DEBUG
    /// Development only: shows a HUD event without changing the system, for outputs without software
    /// volume or with the lid closed. Post `com.smartwindow.debug.hud` with object
    /// "volume:0.6", "brightness:0.3" or "mute".
    private func startDebugTrigger() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.smartwindow.debug.hud"), object: nil, queue: .main
        ) { [weak self] note in
            let parts = (note.object as? String ?? "").split(separator: ":")
            let level = parts.count > 1 ? Double(parts[1]) ?? 0.5 : 0.5
            let event: SystemHUDEvent
            switch parts.first {
            case "brightness": event = SystemHUDEvent(kind: .brightness, level: level, muted: false)
            case "mute": event = SystemHUDEvent(kind: .volume, level: 0, muted: true)
            default: event = SystemHUDEvent(kind: .volume, level: level, muted: false)
            }
            Task { @MainActor in self?.state.show(event) }
        }
    }
    #endif

    // MARK: - Volume

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Volume and mute of the device; changes to either show the HUD. Covers every property
    /// `SystemMonitorService.fetchOutputVolume` may read: virtual main volume, then the main element's
    /// scalar, then the left and right channels. Repeated callbacks are dropped in `volumeChanged`.
    private static let watchedProperties: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
        (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, 1),
        (kAudioDevicePropertyVolumeScalar, 2),
        (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
    ]

    /// Moves the listeners to the current default output. Switching device is not a volume change,
    /// so its level is only remembered.
    private func attachToDefaultDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        deviceListeners = []
        guard let device = SystemMonitorService.defaultOutputDevice() else {
            self.device = kAudioObjectUnknown
            lastVolume = nil
            return
        }
        self.device = device
        lastVolume = SystemMonitorService.fetchOutputVolume(for: device)
        for (selector, element) in Self.watchedProperties {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.volumeChanged() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func volumeChanged() {
        guard device != kAudioObjectUnknown else { return }
        let current = SystemMonitorService.fetchOutputVolume(for: device)
        // A device without software volume has nothing to show; a repeated callback is not a change.
        guard let volume = current.volume,
              current.volume != lastVolume?.volume || current.muted != lastVolume?.muted else { return }
        lastVolume = current
        state.show(SystemHUDEvent(kind: .volume, level: Double(volume) / 100, muted: current.muted))
    }

    // MARK: - Brightness

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    /// Private DisplayServices call, the only way to read the built-in display's brightness.
    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private static func builtInBrightness() -> Double? {
        guard let getBrightness,
              let display = NSScreen.screens.compactMap(\.displayID).first(where: { CGDisplayIsBuiltin($0) != 0 })
        else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return Double(value)
    }

    private func pollBrightness() {
        guard let level = Self.builtInBrightness(), brightnessDetector.sample(level, at: Date()) else { return }
        state.show(SystemHUDEvent(kind: .brightness, level: level, muted: false))
    }
}
