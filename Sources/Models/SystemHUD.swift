import Foundation

/// A volume, brightness or Focus change shown in the notch wings for a moment.
struct SystemHUDEvent: Equatable {
    enum Kind: Equatable {
        case volume
        case brightness
        case focus
    }

    let kind: Kind
    /// 0...1 as reported by the system; clamped when displayed. A Focus uses 1 for on, 0 for off.
    let level: Double
    /// Output is muted (volume only).
    let muted: Bool
    /// The Focus that turned on or off (Focus only).
    var focus: FocusModeDescriptor? = nil

    init(kind: Kind, level: Double, muted: Bool, focus: FocusModeDescriptor? = nil) {
        self.kind = kind
        self.level = level
        self.muted = muted
        self.focus = focus
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

/// The change currently shown in the notch, cleared shortly after the last one.
@MainActor
final class SystemHUDState: ObservableObject {
    static let shared = SystemHUDState()

    @Published private(set) var event: SystemHUDEvent?

    /// How long the wings stay open after the last change, as in the design.
    private let hideDelay: TimeInterval
    private var hideTimer: Timer?
    /// Lets a timer that already fired skip clearing a newer event.
    private var generation = 0

    init(hideDelay: TimeInterval = 1.6) {
        self.hideDelay = hideDelay
    }

    func show(_ event: SystemHUDEvent) {
        self.event = event
        generation += 1
        let shown = generation
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: hideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == shown else { return }
                self.event = nil
            }
        }
        // Common modes: also fires while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }
}
