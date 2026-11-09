import AppKit
import SwiftUI

// MARK: - Routing

/// What the HUD wings draw for an event. Volume and brightness share the level bar; a device never
/// falls back to it.
enum NotchHUDContent: Equatable {
    case level
    case focus
    case device(DeviceHUDPresentation)

    init(_ event: SystemHUDEvent) {
        switch event.kind {
        case .volume, .brightness: self = .level
        case .focus: self = .focus
        case .device:
            // A device event always carries its device; without one there is nothing to show but a
            // generic connect, never a brightness bar.
            self = .device(event.devicePresentation ?? DeviceHUDPresentation(DeviceEvent(
                change: .connected,
                device: DeviceInfo(id: "", name: "Device", kind: .generic, batteries: [], transport: .bluetooth))))
        }
    }
}

// MARK: - Geometry

extension NotchLayout {
    /// The drop card (design/notch-device-hud/03-drop-card.html): 400 pt wide, 134 pt tall with a
    /// 32 pt compact row. The body below the row keeps its height whatever the row height.
    static let deviceCardMinWidth: CGFloat = 400
    static let deviceCardBodyHeight: CGFloat = 102
    /// Device wings need room for an icon and a two-line name, and for "Disconnected": on a MacBook
    /// they open to about 440 pt, as in the design.
    static let deviceMinWingWidth: CGFloat = 126
    /// Clearance from the card's outer edge (its corners are rounder than the wings').
    static let deviceCardEdgeInset: CGFloat = 16

    /// Device wing width: the level wings, widened to fit the name and value.
    var deviceWingWidth: CGFloat { max(hudWingWidth, Self.deviceMinWingWidth) }
    var deviceWingsWidth: CGFloat { notchWidth + deviceWingWidth * 2 }

    /// The card's width, compact row included; wider only around a camera notch it could not fit.
    var deviceCardWidth: CGFloat { max(Self.deviceCardMinWidth, notchWidth + Self.minWingWidth * 2) }
    /// The card's height, compact row included.
    var deviceCardHeight: CGFloat { barHeight + Self.deviceCardBodyHeight }

    private func deviceStyle(_ event: SystemHUDEvent) -> DeviceHUDPresentation.Style? {
        event.kind == .device ? (event.devicePresentation?.style ?? .wings) : nil
    }

    /// Width of each wing while the event shows.
    func hudWingWidth(for event: SystemHUDEvent) -> CGFloat {
        switch deviceStyle(event) {
        case .card: return (deviceCardWidth - notchWidth) / 2
        case .wings: return deviceWingWidth
        case nil: return hudWingWidth
        }
    }

    /// The compact row's width while the event shows. It only grows sideways around the camera.
    func hudRowWidth(for event: SystemHUDEvent) -> CGFloat {
        notchWidth + hudWingWidth(for: event) * 2
    }

    /// Height of the drawn shape while the event shows: the row, or the row and the card below it.
    func hudShapeHeight(for event: SystemHUDEvent) -> CGFloat {
        deviceStyle(event) == .card ? deviceCardHeight : barHeight
    }

    /// Room for a device wing's content, between the outer edge inset and the camera inset.
    func deviceWingContentWidth(for event: SystemHUDEvent) -> CGFloat {
        let edge = deviceStyle(event) == .card ? Self.deviceCardEdgeInset : Self.hudEdgeInset
        return max(0, hudWingWidth(for: event) - edge - Self.hudCameraInset)
    }

    /// Size of the drawn shape (plus the bottom shadow padding) while the event shows. The open
    /// drawer hides the HUD, so it keeps its own size.
    func panelSize(expanded: Bool, hudEvent: SystemHUDEvent?) -> CGSize {
        guard !expanded, let hudEvent else { return panelSize(expanded: expanded) }
        return CGSize(width: hudRowWidth(for: hudEvent), height: hudShapeHeight(for: hudEvent) + Self.bottomPadding)
    }

    /// The drawn part of the window while the event shows, from its top-left corner.
    func visibleRect(expanded: Bool, hudEvent: SystemHUDEvent?) -> CGRect {
        guard !expanded, let hudEvent else { return visibleRect(expanded: expanded) }
        let width = hudRowWidth(for: hudEvent)
        return CGRect(x: (windowSize.width - width) / 2, y: 0, width: width, height: hudShapeHeight(for: hudEvent))
    }

    /// Where the pointer counts (hover opens the drawer, clicks are taken): the compact pill or the
    /// open drawer. HUD wings and the device card never count, so clicks there reach the window below.
    func hoverRect(expanded: Bool, hudEvent: SystemHUDEvent? = nil) -> CGRect {
        // An event HUD is a notification, not a hover target. Preserve the existing drawer's
        // interaction if it was already open (HUD content is suppressed in that state).
        if !expanded, hudEvent?.kind == .device { return .zero }
        return visibleRect(expanded: expanded)
    }
}

// MARK: - Screen reader

/// Turns the shown HUD event into one sentence per device event, however often it is republished.
struct DeviceHUDAnnouncer {
    private var last: SystemHUDEvent?

    mutating func sentence(for event: SystemHUDEvent?) -> String? {
        defer { last = event }
        guard let event, event != last, let presentation = event.devicePresentation else { return nil }
        return presentation.accessibilityLabel
    }

    /// Asks VoiceOver to read the sentence; the notch panel never takes focus, so it would not otherwise.
    static func post(_ sentence: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: sentence,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

// MARK: - Colors

extension DeviceHUDPresentation.Tone {
    /// Colors of the design; the word Low always goes with amber and red.
    var color: Color {
        switch self {
        case .normal: return DeviceHUDColors.text
        case .amber: return Color(red: 1, green: 159 / 255, blue: 10 / 255)
        case .red: return Color(red: 1, green: 69 / 255, blue: 58 / 255)
        case .charging: return DeviceHUDColors.green
        case .off: return DeviceHUDColors.off
        }
    }
}

enum DeviceHUDColors {
    static let text = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let muted = text.opacity(0.62)
    static let off = text.opacity(0.5)
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
}

// MARK: - Wings

/// The compact row while a device event shows: icon (and name, in the wings) left of the camera,
/// the value right of it. Nothing is drawn in the camera gap.
struct DeviceHUDRow: View {
    let presentation: DeviceHUDPresentation
    let wingWidth: CGFloat
    let notchWidth: CGFloat
    let hasNotch: Bool
    var animated = true

    var body: some View {
        let isCard = presentation.style == .card
        let edge = isCard ? NotchLayout.deviceCardEdgeInset : NotchLayout.hudEdgeInset
        HStack(spacing: 0) {
            DeviceHUDLeadingWing(presentation: presentation, animated: animated)
                .padding(.leading, edge)
                .padding(.trailing, NotchLayout.hudCameraInset)
                .frame(width: wingWidth, alignment: isCard ? .center : .leading)
            Color.clear
                .frame(width: notchWidth)
            DeviceHUDTrailingWing(presentation: presentation, animated: animated)
                .padding(.leading, NotchLayout.hudCameraInset)
                .padding(.trailing, edge)
                .frame(width: wingWidth, alignment: isCard ? .center : .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

/// Left wing: the device icon, gray once disconnected, and in the wings its name on up to two lines.
/// Over the card the title below names it.
struct DeviceHUDLeadingWing: View {
    let presentation: DeviceHUDPresentation
    var animated = true

    var body: some View {
        let gone = presentation.tone == .off
        HStack(spacing: 6) {
            DeviceGlyph(presentation: presentation, animated: animated)
            if presentation.style == .wings {
                Text(presentation.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(gone ? DeviceHUDColors.off : DeviceHUDColors.text)
                    .lineLimit(2)
                    .lineSpacing(-1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Right wing: the battery and its percentage, Connected or Disconnected; over the card, what
/// happened (Low battery, Charging or Connected).
struct DeviceHUDTrailingWing: View {
    let presentation: DeviceHUDPresentation
    var animated = true

    var body: some View {
        Group {
            if presentation.style == .card {
                cardStatus
            } else {
                switch presentation.indicator {
                case .battery(let level):
                    HStack(spacing: 5) {
                        DeviceBatteryMark(level: level, tone: presentation.tone, animated: animated && presentation.isLow)
                        Text(presentation.valueText)
                            .foregroundColor(presentation.isLow ? presentation.tone.color : DeviceHUDColors.text)
                            .monospacedDigit()
                        if let tag = presentation.lowTag {
                            DeviceLowTag(text: tag, tone: presentation.tone)
                        }
                    }
                case .hollowDot:
                    state(dot: false, text: presentation.valueText)
                case .connectedDot, .none:
                    state(dot: true, text: presentation.valueText)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
    }

    /// The low part wins over charging: the card says why it opened.
    @ViewBuilder
    private var cardStatus: some View {
        if let lowest = presentation.parts.filter(\.isLow).compactMap(\.level).min() {
            DeviceLowTag(text: "Low battery", tone: DeviceHUDPresentation.tone(level: lowest, charging: false))
        } else if presentation.isCharging {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DeviceHUDColors.green)
                Text("Charging")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(DeviceHUDColors.text)
            }
        } else {
            state(dot: true, text: presentation.valueText)
        }
    }

    private func state(dot filled: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? DeviceHUDColors.green : Color.clear)
                .overlay(Circle().strokeBorder(filled ? Color.clear : DeviceHUDColors.off, lineWidth: 1.5))
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(filled ? DeviceHUDColors.text : DeviceHUDColors.off)
        }
    }
}

/// Device icon. A connect pops it in, like the Focus glyph; Reduce Motion shows it still.
private struct DeviceGlyph: View {
    let presentation: DeviceHUDPresentation
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        let gone = presentation.tone == .off
        let animates = animated && !gone && !reduceMotion
        Image(systemName: presentation.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(gone ? DeviceHUDColors.off : DeviceHUDColors.text)
            .frame(width: 18, height: 18)
            .scaleEffect(popped || !animates ? 1 : 0.4)
            .accessibilityHidden(true)
            .onAppear {
                guard animates else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.08)) { popped = true }
            }
    }
}

/// Battery outline filled to the level, green with a bolt while charging. A low battery nudges twice.
struct DeviceBatteryMark: View {
    let level: Int
    let tone: DeviceHUDPresentation.Tone
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudged = false

    var body: some View {
        let outline = Color.white.opacity(0.55)
        HStack(spacing: 0.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(outline, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tone.color)
                    .frame(width: max(1.5, 15 * CGFloat(level) / 100), height: 5)
                    .padding(.leading, 2.5)
                if tone == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 10)
                }
            }
            .frame(width: 20, height: 10)
            RoundedRectangle(cornerRadius: 1)
                .fill(outline)
                .frame(width: 1.5, height: 3)
        }
        .scaleEffect(nudged ? 1.18 : 1)
        .accessibilityHidden(true)
        .onAppear {
            guard animated, !reduceMotion else { return }
            for (step, grown) in [true, false, true, false].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 + Double(step) * 0.25) {
                    withAnimation(.easeInOut(duration: 0.25)) { nudged = grown }
                }
            }
        }
    }
}

/// "Low" or "Low battery" in an outlined tag, so the color is never alone.
struct DeviceLowTag: View {
    let text: String
    let tone: DeviceHUDPresentation.Tone
    var size: CGFloat = 8.5

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .heavy))
            .tracking(size * 0.04)
            .foregroundColor(tone.color)
            .padding(.horizontal, size < 8 ? 3 : 4)
            .padding(.vertical, size < 8 ? 0 : 1)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(tone.color, lineWidth: 1))
            .fixedSize()
    }
}

// MARK: - Drop card

/// Below the compact row: the full device name and one ring per battery part.
struct DeviceHUDCardBody: View {
    let presentation: DeviceHUDPresentation
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Text(presentation.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DeviceHUDColors.text)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 0) {
                ForEach(Array(presentation.parts.enumerated()), id: \.offset) { _, part in
                    DeviceBatteryRing(part: part)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, NotchLayout.deviceCardEdgeInset)
        .padding(.bottom, 12)
        .frame(width: width, height: NotchLayout.deviceCardBodyHeight, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// One battery part: a ring filled to its level, or a dashed ring and "Not reported", never 0 %.
struct DeviceBatteryRing: View {
    let part: DeviceHUDPresentation.Part

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let level = part.level {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(part.tone.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(part.text)
                        .foregroundColor(part.isLow ? part.tone.color : DeviceHUDColors.text)
                        .monospacedDigit()
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 4, dash: [3, 4]))
                    Text("—")
                        .foregroundColor(DeviceHUDColors.muted)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .frame(width: 36, height: 36)
            .padding(4)
            caption
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(DeviceHUDColors.muted)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var caption: some View {
        if part.level == nil {
            Text("\(part.label) · \(part.text)")
        } else {
            HStack(spacing: 3) {
                if part.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DeviceHUDColors.green)
                }
                Text(part.isCharging ? "\(part.label) · Charging" : part.label)
                if part.isLow {
                    DeviceLowTag(text: "Low", tone: part.tone, size: 7.5)
                }
            }
        }
    }
}

// MARK: - Debug trigger

#if DEBUG
/// Development only: sample device events for previewing every HUD state without the devices.
/// Post `com.smartwindow.debug.device` with object "airpods", "airpods-nocase", "airpods-charging",
/// "airpods-low", "airpods-off", "nuphy", "nuphy-charging", "mouse", "mouse-off", "zone", "trackpad-low",
/// "xbox", "generic" or "wake" (three queued events), e.g.
/// `swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.smartwindow.debug.device"), object: "airpods", userInfo: nil, deliverImmediately: true)'`.
enum DeviceHUDDebugSamples {
    static let notification = Notification.Name("com.smartwindow.debug.device")

    static func events(named name: String) -> [SystemHUDEvent] {
        func device(_ name: String, _ kind: DeviceKind, _ batteries: [DeviceBattery] = []) -> DeviceInfo {
            DeviceInfo(id: "debug-\(name)", name: name, kind: kind, batteries: batteries, transport: .bluetooth)
        }
        func pods(_ left: Int?, _ right: Int?, _ chargingCase: Int?, caseCharging: Bool = false) -> DeviceInfo {
            device("Kevnnard's AirPods", .airpods, [
                DeviceBattery(part: .left, level: left), DeviceBattery(part: .right, level: right),
                DeviceBattery(part: .chargingCase, level: chargingCase, isCharging: caseCharging)])
        }
        func event(_ change: DeviceEvent.Change, _ device: DeviceInfo) -> SystemHUDEvent {
            SystemHUDEvent(device: DeviceEvent(change: change, device: device))
        }
        let nuphy = device("NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 62)])
        let mouse = device("BT5.0 Mouse", .mouse)
        switch name {
        case "airpods-nocase": return [event(.connected, pods(80, 76, nil))]
        case "airpods-charging": return [event(.connected, pods(80, 76, 45, caseCharging: true))]
        case "airpods-low": return [event(.droppedLow, pods(9, 31, nil))]
        case "airpods-off": return [event(.disconnected, pods(80, 76, 45))]
        case "nuphy": return [event(.connected, nuphy)]
        case "nuphy-charging":
            return [event(.connected, device("NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 62, isCharging: true)]))]
        case "mouse": return [event(.connected, mouse)]
        case "mouse-off": return [event(.disconnected, mouse)]
        case "zone": return [event(.connected, device("Zone Vibe 125", .headset, [DeviceBattery(part: .main, level: 18)]))]
        case "trackpad-low":
            return [event(.droppedLow, device("Magic Trackpad", .trackpad, [DeviceBattery(part: .main, level: 8)]))]
        case "xbox":
            return [event(.connected, device("Xbox Wireless Controller", .gameController, [DeviceBattery(part: .main, level: 54)]))]
        case "generic": return [event(.connected, device("HC-05", .generic))]
        case "wake": return [event(.connected, pods(80, 76, 45)), event(.connected, mouse), event(.connected, nuphy)]
        default: return [event(.connected, pods(80, 76, 45))]
        }
    }
}
#endif
