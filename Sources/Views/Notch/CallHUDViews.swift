import AppKit
import SwiftUI

// Call HUD (design/notch-call-hud/03-call-card.html): a card drops when a call starts, folds into
// wings (app badge and waveform left of the camera, green timer right of it), drops again on hover,
// and shows the total when the call ends.

// MARK: - Routing

/// How the notch shows the call, if at all.
enum NotchCallMode: Equatable {
    case none
    case wings
    case card

    /// Volume, brightness, Focus and device HUDs flash over the call and give it back, also over a
    /// card opened by hover: it has no controls to protect, unlike the media drawer. Hovering opens
    /// the call card instead of the media drawer.
    init(call: CallHUDPresentation?, hudEvent: SystemHUDEvent?, expanded: Bool, startCard: Bool) {
        guard let call, hudEvent == nil else {
            self = .none
            return
        }
        self = expanded || call.phase == .ended || startCard ? .card : .wings
    }
}

// MARK: - Geometry

extension NotchLayout {
    /// Call wings: about 440 pt on a MacBook, 360 pt without a camera notch, as in the design.
    static let callMinWingWidth: CGFloat = 128
    static let callMinHalfWidth: CGFloat = 180

    var callWingsWidth: CGFloat { notchWidth + callWingWidth(for: .wings) * 2 }
    /// The device drop card's size, but never narrower than the wings: the card opens on hover, and
    /// narrowing under the pointer would close it again.
    var callCardWidth: CGFloat { max(deviceCardWidth, notchWidth + callWingWidth(for: .wings) * 2) }
    var callCardHeight: CGFloat { deviceCardHeight }

    func callWingWidth(for mode: NotchCallMode) -> CGFloat {
        switch mode {
        case .card: return (callCardWidth - notchWidth) / 2
        case .wings, .none: return max(hudWingWidth, hasNotch ? Self.callMinWingWidth : Self.callMinHalfWidth)
        }
    }

    func callRowWidth(for mode: NotchCallMode) -> CGFloat { notchWidth + callWingWidth(for: mode) * 2 }

    /// Where the pointer counts during a call: the compact row, folded or under the start and end
    /// cards (so a card that drops on its own does not grab the windows below), or the whole card
    /// once hover opened it.
    func hoverRect(expanded: Bool, callMode: NotchCallMode) -> CGRect {
        guard callMode != .none else { return hoverRect(expanded: expanded) }
        let width = callRowWidth(for: callMode)
        let height = expanded && callMode == .card ? callCardHeight : barHeight
        return CGRect(x: (windowSize.width - width) / 2, y: 0, width: width, height: height)
    }

    /// The panel's hover area for everything the notch can show.
    func hoverRect(expanded: Bool, hudEvent: SystemHUDEvent?, call: CallHUDPresentation?, startCard: Bool) -> CGRect {
        let mode = NotchCallMode(call: call, hudEvent: hudEvent, expanded: expanded, startCard: startCard)
        guard mode == .none else { return hoverRect(expanded: expanded, callMode: mode) }
        // A HUD over a call: the drawer never opens during a call, so the HUD row is all there is.
        if call != nil, hudEvent != nil { return hoverRect(expanded: false, hudEvent: hudEvent) }
        return hoverRect(expanded: expanded, hudEvent: hudEvent)
    }
}

// MARK: - Screen reader

/// One sentence when a call starts and one when it ends, however often the state republishes.
struct CallHUDAnnouncer {
    private var last: (confirmedAt: Date, phase: CallHUDPresentation.Phase)?

    mutating func sentence(for presentation: CallHUDPresentation?) -> String? {
        guard let presentation else { return nil }
        let key = (presentation.session.confirmedAt, presentation.phase)
        if let last, last.confirmedAt == key.0, last.phase == key.1 { return nil }
        last = key
        return presentation.sentence
    }
}

// MARK: - Colors

enum CallHUDColors {
    static let green = DeviceHUDColors.green
    static let red = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
    static let text = DeviceHUDColors.text
    static let muted = DeviceHUDColors.muted
    static let off = DeviceHUDColors.off

    /// Badge color of each app or web service when its icon is not installed; others use the Meet green.
    static func badge(named name: String) -> Color {
        switch name {
        case "Zoom": return Color(red: 11 / 255, green: 92 / 255, blue: 255 / 255)
        case "WhatsApp": return Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)
        case "Teams": return Color(red: 80 / 255, green: 89 / 255, blue: 201 / 255)
        case "Discord": return Color(red: 88 / 255, green: 101 / 255, blue: 242 / 255)
        case "Slack": return Color(red: 74 / 255, green: 21 / 255, blue: 75 / 255)
        case "Webex": return Color(red: 0 / 255, green: 160 / 255, blue: 209 / 255)
        case "Skype": return Color(red: 0 / 255, green: 175 / 255, blue: 240 / 255)
        case "Telegram": return Color(red: 42 / 255, green: 171 / 255, blue: 238 / 255)
        case "Signal": return Color(red: 58 / 255, green: 118 / 255, blue: 240 / 255)
        case "FaceTime": return green
        default: return Color(red: 30 / 255, green: 142 / 255, blue: 62 / 255)
        }
    }
}

// MARK: - Row

/// The compact row during a call. Nothing is drawn in the camera gap.
struct CallHUDRow: View {
    let presentation: CallHUDPresentation
    let mode: NotchCallMode
    let wingWidth: CGFloat
    let notchWidth: CGFloat
    var animated = true

    var body: some View {
        let isCard = mode == .card
        let edge = isCard ? NotchLayout.deviceCardEdgeInset : NotchLayout.hudEdgeInset
        let ended = presentation.phase == .ended
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                CallBadge(presentation: presentation, ended: ended)
                // Over the card the big waveform below takes over.
                if !isCard && !ended {
                    CallWaveform(count: 7, maxHeight: 16, barWidth: 2.5, spacing: 2, animated: animated)
                }
            }
            .padding(.leading, edge)
            .padding(.trailing, NotchLayout.hudCameraInset)
            .frame(width: wingWidth, alignment: isCard ? .center : .leading)
            Color.clear
                .frame(width: notchWidth)
            Group {
                if ended {
                    Text("Ended")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(CallHUDColors.red)
                } else {
                    CallTimer(presentation: presentation, animated: animated)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, NotchLayout.hudCameraInset)
            .padding(.trailing, edge)
            .frame(width: wingWidth, alignment: isCard ? .center : .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ended ? "\(presentation.title) call ended" : "\(presentation.title) call")
        .accessibilityValue(presentation.timer(at: Date()))
    }
}

/// Icons of installed apps, from macOS, so they are always the official ones.
@MainActor
enum CallAppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { rasterized(NSWorkspace.shared.icon(forFile: $0.path)) }
        cache[bundleID] = icon
        return icon
    }

    /// One plain sRGB bitmap at the badge's largest size, instead of the icon's many
    /// representations (some tinted or wide-gamut) redrawn on every frame.
    private static func rasterized(_ icon: NSImage, pixels: Int = 64) -> NSImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .retagging(with: .sRGB) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(rep)
        return image
    }

    /// The service's own app when installed (Zoom, Teams…); the call app for a native call or an
    /// unknown site; nil for a service with no app (Meet), which gets a colored badge.
    static func icon(for presentation: CallHUDPresentation) -> NSImage? {
        guard let service = presentation.service else { return icon(bundleID: presentation.app.bundleID) }
        return service.iconBundleIDs.lazy.compactMap { icon(bundleID: $0) }.first
    }
}

/// The app's official icon while live, with a small browser mark for a web call; a red hang-up
/// once ended.
struct CallBadge: View {
    let presentation: CallHUDPresentation
    let ended: Bool

    var body: some View {
        if ended {
            symbolBadge("phone.down.fill", color: CallHUDColors.red)
        } else {
            main
                .frame(width: 18, height: 18)
                .overlay(alignment: .bottomTrailing) {
                    if presentation.via != nil, let browser = CallAppIcons.icon(bundleID: presentation.app.bundleID) {
                        Image(nsImage: browser)
                            .resizable()
                            .frame(width: 11, height: 11)
                            .background(Circle().fill(Color.black).padding(-0.5))
                            .offset(x: 4, y: 4)
                    }
                }
        }
    }

    @ViewBuilder
    private var main: some View {
        if let icon = CallAppIcons.icon(for: presentation) {
            // App icons carry a transparent margin; scale it away so the tile fills 18 pt.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaleEffect(1.2)
        } else {
            symbolBadge("video.fill", color: CallHUDColors.badge(named: presentation.title))
        }
    }

    private func symbolBadge(_ symbol: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white))
    }
}

/// The running time, green, redrawn every second; frozen once ended.
struct CallTimer: View {
    let presentation: CallHUDPresentation
    var animated = true

    var body: some View {
        if animated && presentation.phase == .live {
            TimelineView(.periodic(from: presentation.session.startedAt, by: 1)) { context in
                text(at: context.date)
            }
        } else {
            text(at: Date())
        }
    }

    private func text(at date: Date) -> some View {
        Text(presentation.timer(at: date))
            .monospacedDigit()
            .foregroundColor(CallHUDColors.green)
    }
}

/// Green bars that follow the microphone level. Without the Microphone permission (or with the
/// meter stopped) they pulse slowly on their own, so they read as live but not as your voice.
struct CallWaveform: View {
    let count: Int
    let maxHeight: CGFloat
    let barWidth: CGFloat
    let spacing: CGFloat
    var animated = true
    @ObservedObject private var mic = MicLevelState.shared

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                bars(at: context.date)
            }
        } else {
            bars(at: Date(timeIntervalSince1970: 0.4))
        }
    }

    private func bars(at date: Date) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        let level = mic.isMetering ? mic.level : 0.22 + 0.12 * sin(time * 2.2)
        // A new jitter about 12 times a second; the decorative pulse changes slower.
        let seed = Int(time * (mic.isMetering ? 12 : 3))
        let heights = MicLevel.barHeights(level: level, count: count, maxHeight: Double(maxHeight),
                                          minHeight: 3, seed: seed)
        return HStack(spacing: spacing) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(CallHUDColors.green)
                    .frame(width: barWidth, height: CGFloat(heights[index]))
            }
        }
        .frame(height: maxHeight)
        .animation(animated ? .linear(duration: 0.09) : nil, value: heights)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

/// Below the compact row: "<App> · Call", the big waveform and the timer; once ended,
/// "<App> · Call ended" and the total.
struct CallHUDCardBody: View {
    let presentation: CallHUDPresentation
    let width: CGFloat
    var animated = true

    var body: some View {
        let ended = presentation.phase == .ended
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(presentation.title)
                    .foregroundColor(CallHUDColors.text)
                Text(ended ? "· Call ended" : "· Call")
                    .foregroundColor(CallHUDColors.muted)
                    .fontWeight(.medium)
                if let via = presentation.via {
                    Text("· in \(via)")
                        .foregroundColor(CallHUDColors.muted)
                        .fontWeight(.medium)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            if ended {
                Text(presentation.timer(at: Date()))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(CallHUDColors.off)
                Spacer(minLength: 0)
            } else {
                CallWaveform(count: 24, maxHeight: 38, barWidth: 3, spacing: 3, animated: animated)
                Spacer(minLength: 0)
                CallTimer(presentation: presentation, animated: animated)
                    .font(.system(size: 18, weight: .bold))
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(width: width, height: NotchLayout.deviceCardBodyHeight, alignment: .top)
        .accessibilityHidden(true)
    }
}
