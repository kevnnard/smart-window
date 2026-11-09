import AppKit
import SwiftUI

// Device HUD views (design/notch-device-hud/03-drop-card.html): which content a HUD event routes to,
// the wings and 400×134 drop card geometry on notched and external screens, the fixed notch window,
// pointer pass-through over the wings and the card, content fitting the wings, and one screen reader
// sentence per event. Set DEVICEHUD_RENDER=1 to also write PNGs under /tmp/devicehud/.
@main
@MainActor
struct DeviceHUDViewProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func device(_ name: String, _ kind: DeviceKind, _ batteries: [DeviceBattery] = []) -> DeviceInfo {
        DeviceInfo(id: name, name: name, kind: kind, batteries: batteries, transport: .bluetooth)
    }

    static func event(_ change: DeviceEvent.Change, _ device: DeviceInfo) -> SystemHUDEvent {
        SystemHUDEvent(device: DeviceEvent(change: change, device: device))
    }

    static let pods = device("Kevnnard's AirPods", .airpods, [
        DeviceBattery(part: .left, level: 80), DeviceBattery(part: .right, level: 76),
        DeviceBattery(part: .chargingCase, level: 45)])
    static let podsLow = device("Kevnnard's AirPods", .airpods, [
        DeviceBattery(part: .left, level: 9), DeviceBattery(part: .right, level: 31),
        DeviceBattery(part: .chargingCase, level: nil)])
    static let podsCharging = device("Kevnnard's AirPods", .airpods, [
        DeviceBattery(part: .left, level: 80), DeviceBattery(part: .right, level: 76),
        DeviceBattery(part: .chargingCase, level: 45, isCharging: true)])
    static let nuphy = device("NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 62)])
    static let nuphyCharging = device("NuPhy Air75 V2", .keyboard, [DeviceBattery(part: .main, level: 62, isCharging: true)])
    static let mouse = device("BT5.0 Mouse", .mouse)
    static let trackpad = device("Magic Trackpad", .trackpad, [DeviceBattery(part: .main, level: 8)])
    static let zone = device("Zone Vibe 125", .headset, [DeviceBattery(part: .main, level: 18)])
    static let xbox = device("Xbox Wireless Controller", .gameController, [DeviceBattery(part: .main, level: 54)])

    static let samples: [(String, SystemHUDEvent)] = [
        ("airpods-card", event(.connected, pods)),
        ("airpods-low-no-case", event(.droppedLow, podsLow)),
        ("airpods-case-charging", event(.connected, podsCharging)),
        ("nuphy-62", event(.connected, nuphy)),
        ("nuphy-charging", event(.connected, nuphyCharging)),
        ("mouse-connected", event(.connected, mouse)),
        ("trackpad-8-low", event(.droppedLow, trackpad)),
        ("zone-18-low", event(.connected, zone)),
        ("xbox-long-name", event(.connected, xbox)),
        ("airpods-disconnected", event(.disconnected, pods)),
        ("mouse-disconnected", event(.disconnected, mouse)),
    ]

    static func main() {
        _ = NSApplication.shared

        // Routing: a device event is never drawn as brightness.
        let card = event(.connected, pods)
        let wings = event(.connected, nuphy)
        check(NotchHUDContent(card) == .device(card.devicePresentation!), "a card device event routes to device content")
        check(NotchHUDContent(wings) == .device(wings.devicePresentation!), "a wings device event routes to device content")
        check(NotchHUDContent(event(.disconnected, pods)) != .level, "a disconnect is not the level bar")
        check(NotchHUDContent(SystemHUDEvent(kind: .brightness, level: 0.4, muted: false)) == .level, "brightness")
        check(NotchHUDContent(SystemHUDEvent(kind: .volume, level: 0.4, muted: false)) == .level, "volume")
        check(NotchHUDContent(SystemHUDEvent(focus: .generic, isOn: true)) == .focus, "Focus")

        // Geometry on every kind of screen: MacBook at default, tightest and tallest sizes, and
        // external pills at default and the Settings minimum and maximum.
        let layouts: [(String, NotchLayout)] = [
            ("macbook", NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 280, customHeight: 32)),
            ("macbook-tight", NotchLayout(notchWidth: 185, physicalBarHeight: 38, customWidth: 180, customHeight: 30)),
            ("macbook-tall", NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 440, customHeight: 46)),
            ("external", NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 280, customHeight: 32)),
            ("external-narrow", NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 180, customHeight: 30)),
            ("external-wide", NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 440, customHeight: 46)),
        ]
        let margin = NotchLayout.shadowMargin
        for (name, layout) in layouts {
            let compact = layout.visibleRect(expanded: false)
            let cardRect = layout.visibleRect(expanded: false, hudEvent: card)
            let wingsRect = layout.visibleRect(expanded: false, hudEvent: wings)
            check(layout.deviceCardWidth == 400 || (layout.hasNotch && layout.deviceCardWidth > 400),
                  "\(name): the card is 400 pt wide, got \(layout.deviceCardWidth)")
            check(layout.deviceCardHeight == layout.barHeight + NotchLayout.deviceCardBodyHeight,
                  "\(name): the card is the compact row plus its body")
            check(cardRect.width == layout.deviceCardWidth && cardRect.height == layout.deviceCardHeight,
                  "\(name): the card's drawn rect, got \(cardRect)")
            // The compact row does not move: same top, same center, same height.
            for rect in [cardRect, wingsRect] {
                check(rect.minY == 0 && abs(rect.midX - compact.midX) < 0.001, "\(name): HUD stays centered on top")
            }
            check(wingsRect.height == layout.barHeight, "\(name): wings keep the row height")
            // The window never resizes; it already fits the card, the wings and the drawer with the shadow.
            let window = layout.windowSize
            check(window.width >= layout.deviceCardWidth + margin * 2, "\(name): window fits the card width, got \(window)")
            check(window.width >= layout.deviceWingsWidth + margin * 2, "\(name): window fits the device wings")
            check(window.width >= layout.hudWidth + margin * 2, "\(name): window fits the level wings")
            check(window.width >= layout.expandedWidth + margin * 2, "\(name): window fits the drawer")
            check(window.height >= layout.deviceCardHeight + NotchLayout.bottomPadding + margin,
                  "\(name): window fits the card height, got \(window)")
            check(cardRect.minX >= margin && cardRect.maxX <= window.width - margin, "\(name): the card shadow is not cut")
            let panel = layout.panelSize(expanded: false, hudEvent: card)
            check(panel.width == layout.deviceCardWidth && panel.height == layout.deviceCardHeight + NotchLayout.bottomPadding,
                  "\(name): the card panel size")
            check(layout.panelSize(expanded: true, hudEvent: card) == layout.panelSize(expanded: true),
                  "\(name): the open drawer ignores the card")
            // Nothing in the camera gap: the wings plus the gap are the whole row.
            check(abs(layout.hudWingWidth(for: card) * 2 + layout.notchWidth - layout.deviceCardWidth) < 0.001,
                  "\(name): card wings surround the camera gap")
            check(abs(layout.hudWingWidth(for: wings) * 2 + layout.notchWidth - layout.deviceWingsWidth) < 0.001,
                  "\(name): device wings surround the camera gap")
            check(layout.hudRowWidth(for: SystemHUDEvent(kind: .volume, level: 0.5, muted: false)) == layout.hudWidth,
                  "\(name): the volume HUD keeps its width")
            check(layout.deviceWingsWidth >= layout.hudWidth, "\(name): device wings are at least the level wings")
            check(!layout.hasNotch || layout.deviceWingsWidth <= 440 || layout.wingWidth > NotchLayout.deviceMinWingWidth,
                  "\(name): MacBook device wings stay within 440 pt, got \(layout.deviceWingsWidth)")

            // Hover and clicks count only over the compact pill: never the wings or the card.
            check(layout.hoverRect(expanded: false) == compact, "\(name): ordinary hover stays the compact pill")
            let hover = layout.hoverRect(expanded: false, hudEvent: card)
            check(hover.isEmpty, "\(name): the entire device card is pass-through")
            check(layout.hoverRect(expanded: false, hudEvent: wings).isEmpty,
                  "\(name): the entire device wings HUD is pass-through")
            check(!hover.contains(CGPoint(x: cardRect.midX, y: layout.barHeight + 40)), "\(name): the card body is not hover")
            let cardTip = CGPoint(x: cardRect.minX + 4, y: 4)
            check(!hover.contains(cardTip), "\(name): the card wing tip is pass-through")
            check(!hover.contains(CGPoint(x: wingsRect.maxX - 4, y: 4)), "\(name): the device wing tip is not hover")

            // Content fits inside its wing at the row height.
            for (sample, hud) in samples {
                guard let presentation = hud.devicePresentation else { continue }
                let wing = layout.hudWingWidth(for: hud)
                let room = layout.deviceWingContentWidth(for: hud)
                check(room > 0 && room <= wing, "\(name)/\(sample): content room inside the wing")
                let left = fitting(DeviceHUDLeadingWing(presentation: presentation, animated: false), width: room)
                let right = fitting(DeviceHUDTrailingWing(presentation: presentation, animated: false), width: nil)
                check(left.height <= layout.barHeight, "\(name)/\(sample): left wing height \(left.height) > \(layout.barHeight)")
                check(right.width <= room + 0.5, "\(name)/\(sample): right wing \(right.width) > \(room)")
                check(right.height <= layout.barHeight, "\(name)/\(sample): right wing height \(right.height)")
                if presentation.style == .card {
                    let body = fitting(DeviceHUDCardBody(presentation: presentation, width: layout.deviceCardWidth),
                                       width: layout.deviceCardWidth)
                    check(body.height <= NotchLayout.deviceCardBodyHeight + 0.5, "\(name)/\(sample): card body \(body)")
                }
            }
        }

        // In the real window: the pointer over the card or a wing tip lets clicks through and does not
        // open the drawer.
        let layout = layouts[0].1
        let state = NotchPanelState()
        let host = NotchHostingView(rootView: Color.clear, panelState: state,
                                    hoverRect: { layout.hoverRect(expanded: state.isExpanded, hudEvent: card) })
        let size = layout.windowSize
        let origin = CGPoint(x: 1000, y: 1000 - size.height)
        let window = NotchOverlayWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [],
                                        backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        let cardRect = layout.visibleRect(expanded: false, hudEvent: card)
        func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x, y: 1000 - point.y) }
        host.updatePointer(at: screen(CGPoint(x: cardRect.midX, y: layout.barHeight + 50)))
        check(window.ignoresMouseEvents && !state.isExpanded, "over the card body, clicks pass through")
        host.updatePointer(at: screen(CGPoint(x: cardRect.minX + 6, y: 10)))
        check(window.ignoresMouseEvents && !state.isExpanded, "over the card's wing tip, clicks pass through")
        host.updatePointer(at: screen(CGPoint(x: cardRect.midX, y: 10)))
        check(window.ignoresMouseEvents && !state.isExpanded, "the device HUD compact center also passes clicks through")
        state.collapse()
        window.orderOut(nil)

        // Screen readers: one sentence per event, not per screen or per republish.
        var announcer = DeviceHUDAnnouncer()
        check(announcer.sentence(for: nil) == nil, "nothing shown, nothing said")
        check(announcer.sentence(for: card) == card.devicePresentation?.accessibilityLabel, "a device event is announced")
        check(announcer.sentence(for: card) == nil, "the same event is not announced twice")
        check(announcer.sentence(for: nil) == nil, "hiding says nothing")
        check(announcer.sentence(for: card) != nil, "the same device again, as a new event, is announced")
        check(announcer.sentence(for: SystemHUDEvent(kind: .volume, level: 0.5, muted: false)) == nil,
              "volume is not a device sentence")

        if ProcessInfo.processInfo.environment["DEVICEHUD_RENDER"] != nil {
            render(layouts: [layouts[0], layouts[3]])
        }
        print("PASS: DeviceHUDViewProbe verified")
    }

    static func fitting<V: View>(_ view: V, width: CGFloat?) -> CGSize {
        let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: width == nil, vertical: true))
        return host.fittingSize
    }

    /// The notch as NotchView draws it while the HUD shows, with the camera housing on top.
    struct Preview: View {
        let layout: NotchLayout
        let event: SystemHUDEvent

        var body: some View {
            let presentation = event.devicePresentation!
            let wing = layout.hudWingWidth(for: event)
            let width = layout.hudRowWidth(for: event)
            let isCard = presentation.style == .card
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.09, green: 0.14, blue: 0.25), Color(red: 0.36, green: 0.18, blue: 0.33)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    DeviceHUDRow(presentation: presentation, wingWidth: wing, notchWidth: layout.notchWidth,
                                 hasNotch: layout.hasNotch, animated: false)
                        .frame(width: width, height: layout.barHeight)
                    if isCard {
                        DeviceHUDCardBody(presentation: presentation, width: width)
                    }
                }
                .background(Color.black)
                .clipShape(BottomRoundedRectangle(radius: isCard ? 24 : (layout.hasNotch ? 12 : 14)))
                if layout.hasNotch {
                    // The camera housing has no pixels: anything drawn under it would be lost.
                    Rectangle().fill(Color.red.opacity(0.35))
                        .frame(width: layout.notchWidth, height: layout.physicalBarHeight)
                }
            }
            .frame(width: layout.windowSize.width, height: layout.deviceCardHeight + 30)
        }
    }

    static func render(layouts: [(String, NotchLayout)]) {
        let directory = URL(fileURLWithPath: "/tmp/devicehud")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (screen, layout) in layouts {
            for (sample, hud) in samples {
                let renderer = ImageRenderer(content: Preview(layout: layout, event: hud).environment(\.colorScheme, .dark))
                renderer.scale = 2
                guard let image = renderer.cgImage else { check(false, "render \(sample)"); return }
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                let url = directory.appendingPathComponent("\(screen)-\(sample).png")
                check((try? data?.write(to: url)) != nil, "write \(url.path)")
                print("rendered \(url.path)")
            }
        }
    }
}
