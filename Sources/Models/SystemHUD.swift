import Foundation

/// A volume, brightness, Focus or device change shown in the notch wings for a moment.
struct SystemHUDEvent: Equatable {
    enum Kind: Equatable {
        case volume
        case brightness
        case focus
        case device
    }

    let kind: Kind
    /// 0...1 as reported by the system; clamped when displayed. A Focus uses 1 for on, 0 for off.
    let level: Double
    /// Output is muted (volume only).
    let muted: Bool
    /// The Focus that turned on or off (Focus only).
    var focus: FocusModeDescriptor? = nil
    /// The device that connected, disconnected or ran low (device only).
    var device: DeviceEvent? = nil

    init(kind: Kind, level: Double, muted: Bool, focus: FocusModeDescriptor? = nil) {
        self.kind = kind
        self.level = level
        self.muted = muted
        self.focus = focus
    }

    init(device: DeviceEvent) {
        self.init(kind: .device, level: Double(device.device.lowestLevel ?? 0) / 100, muted: false)
        self.device = device
    }

    /// What the wings or the drop card show for a device event.
    var devicePresentation: DeviceHUDPresentation? {
        device.map(DeviceHUDPresentation.init)
    }

    init(focus: FocusModeDescriptor, isOn: Bool) {
        self.init(kind: .focus, level: isOn ? 1 : 0, muted: false, focus: focus)
    }

    /// A Focus turned on (Focus only).
    var isOn: Bool { level > 0 }

    /// Fill of the level bar.
    var barFraction: Double {
        muted ? 0 : min(1, max(0, level))
    }

    /// Number next to the bar, a dash while muted, or On/Off for a Focus.
    var valueText: String {
        if kind == .focus { return isOn ? "On" : "Off" }
        if let devicePresentation { return devicePresentation.valueText }
        return muted ? "—" : String(Int((barFraction * 100).rounded()))
    }

    /// SF Symbol for the left wing. The speaker waves follow the level through `variableValue`.
    var symbolName: String {
        switch kind {
        case .volume:
            if muted { return "speaker.slash.fill" }
            return barFraction == 0 ? "speaker.fill" : "speaker.wave.3.fill"
        case .brightness:
            return barFraction < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .focus:
            return (focus ?? .generic).symbolName
        case .device:
            return devicePresentation?.symbolName ?? DeviceKind.generic.symbolName
        }
    }
}

/// Tells a brightness change worth showing from the ambient light sensor's slow drift, given the
/// built-in display's brightness sampled every 0.1 s. A key or Control Center step moves it by 1/16
/// over a short fade; automatic brightness moves it a little at a time.
struct BrightnessChangeDetector {
    /// Movement within `stepWindow` that counts as a step, so a step spread over a fade still counts.
    static let stepThreshold = 0.012
    static let stepWindow: TimeInterval = 0.3
    /// After a step, any further movement keeps updating the HUD for this long (the rest of the fade).
    /// It runs from the last step, so drift alone cannot keep it going.
    static let followWindow: TimeInterval = 1.6
    /// Below this, two samples are the same reading.
    static let noise = 0.0005

    private var recent: [(time: Date, level: Double)] = []
    private var last: Double?
    private var lastStep: Date?

    /// Records a sample; returns true when the HUD should show it.
    mutating func sample(_ level: Double, at now: Date) -> Bool {
        defer {
            recent.append((now, level))
            last = level
        }
        recent.removeAll { now.timeIntervalSince($0.time) > Self.stepWindow + 0.001 }
        guard let last, abs(level - last) > Self.noise else { return false }
        let baseline = recent.first?.level ?? last
        if abs(level - baseline) >= Self.stepThreshold {
            lastStep = now
            return true
        }
        return lastStep.map { now.timeIntervalSince($0) < Self.followWindow } ?? false
    }
}

/// The change currently shown in the notch, cleared shortly after the last one. Volume, brightness
/// and Focus replace whatever shows; device events take turns, each for its own duration.
@MainActor
final class SystemHUDState: ObservableObject {
    static let shared = SystemHUDState()

    @Published private(set) var event: SystemHUDEvent?

    /// How long the wings stay open after the last change, as in the design.
    private let hideDelay: TimeInterval
    /// Scales device durations (wings 2 s, card 3 s) and the pause between them; probes shorten it.
    private let deviceTimeScale: Double
    /// Pause between queued device events so each one closes before the next opens.
    private static let deviceGap: TimeInterval = 0.35
    private var hideTimer: Timer?
    /// Device events waiting for their turn.
    private var queue: [SystemHUDEvent] = []
    /// Lets a timer that already fired skip clearing a newer event.
    private var generation = 0

    init(hideDelay: TimeInterval = 1.6, deviceTimeScale: Double = 1) {
        self.hideDelay = hideDelay
        self.deviceTimeScale = deviceTimeScale
    }

    var queuedCount: Int { queue.count }

    func duration(of event: SystemHUDEvent) -> TimeInterval {
        event.devicePresentation.map { $0.duration * deviceTimeScale } ?? hideDelay
    }

    func show(_ event: SystemHUDEvent) {
        if event.kind == .device, self.event?.kind == .device || !queue.isEmpty {
            queue.append(event)
            return
        }
        present(event)
    }

    private func present(_ event: SystemHUDEvent) {
        self.event = event
        schedule(after: duration(of: event)) { [weak self] in
            guard let self else { return }
            self.event = nil
            guard !self.queue.isEmpty else { return }
            self.schedule(after: Self.deviceGap * self.deviceTimeScale) { [weak self] in
                guard let self, !self.queue.isEmpty else { return }
                self.present(self.queue.removeFirst())
            }
        }
    }

    /// Runs `action` after the delay unless something newer was shown or scheduled meanwhile.
    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        generation += 1
        let shown = generation
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == shown else { return }
                action()
            }
        }
        // Common modes: also fires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }
}
