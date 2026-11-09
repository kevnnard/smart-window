import AppKit
import Foundation
import SwiftUI

// Call HUD in the notch: which view shows (wings, card or nothing), the geometry on a MacBook and
// an external display, and the hover area.
@main
@MainActor
struct CallHUDViewProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        let t0 = Date(timeIntervalSince1970: 5_000)
        let app = CallApp(name: "Zoom", bundleID: "us.zoom.xos")
        let live = CallHUDPresentation(CallSession(app: app, startedAt: t0, confirmedAt: t0))
        var endedSession = CallSession(app: app, startedAt: t0, confirmedAt: t0)
        endedSession.endedAt = t0 + 60
        let ended = CallHUDPresentation(endedSession)
        let volume = SystemHUDEvent(kind: .volume, level: 0.5, muted: false)

        // Routing.
        check(NotchCallMode(call: nil, hudEvent: nil, expanded: false, startCard: false) == .none, "no call")
        check(NotchCallMode(call: live, hudEvent: nil, expanded: false, startCard: true) == .card, "start card")
        check(NotchCallMode(call: live, hudEvent: nil, expanded: false, startCard: false) == .wings, "then wings")
        check(NotchCallMode(call: live, hudEvent: nil, expanded: true, startCard: false) == .card,
              "hovering opens the call card instead of the media drawer")
        check(NotchCallMode(call: ended, hudEvent: nil, expanded: false, startCard: false) == .card, "ended card")
        check(NotchCallMode(call: live, hudEvent: volume, expanded: false, startCard: false) == .none,
              "a volume change flashes over the call")
        check(NotchCallMode(call: ended, hudEvent: volume, expanded: false, startCard: false) == .none,
              "also over the ended card")
        check(NotchCallMode(call: live, hudEvent: volume, expanded: true, startCard: false) == .none,
              "the call card has no controls, so a volume change shows over it even while hovered (S10)")
        check(NotchCallMode(call: nil, hudEvent: nil, expanded: true, startCard: false) == .none, "the drawer has no call")
        // While the HUD shows over a hovered call, only the HUD row takes the pointer, never the drawer.
        let device = SystemHUDEvent(device: DeviceEvent(change: .connected,
            device: DeviceInfo(id: "m", name: "Mouse", kind: .generic, batteries: [], transport: .bluetooth)))
        let hoverLayout = NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 280, customHeight: 32)
        check(hoverLayout.hoverRect(expanded: true, hudEvent: volume, call: live, startCard: false)
              == hoverLayout.hoverRect(expanded: false, hudEvent: volume),
              "a volume HUD over the hovered call hovers its row, not the drawer")
        check(hoverLayout.hoverRect(expanded: true, hudEvent: device, call: live, startCard: false) == .zero,
              "a device HUD over the call lets every click through")

        // MacBook: 185 pt camera notch, 32 pt bar.
        let macbook = NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 280, customHeight: 32)
        check(abs(macbook.callWingsWidth - 441) < 0.5, "MacBook call wings about 440 pt: \(macbook.callWingsWidth)")
        check(macbook.callCardWidth == macbook.callWingsWidth, "the card never narrows under the pointer")
        check(macbook.callCardHeight == 134, "card 134 pt with a 32 pt row: \(macbook.callCardHeight)")
        check(macbook.windowSize.width >= macbook.callCardWidth + NotchLayout.shadowMargin * 2, "window fits the card")
        check(macbook.windowSize.height >= macbook.callCardHeight + NotchLayout.shadowMargin, "window fits the card height")

        // External display: no camera notch.
        let external = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 200, customHeight: 32)
        check(external.callWingsWidth == 360, "external call wings 360 pt: \(external.callWingsWidth)")
        check(external.callCardWidth == 400, "external card 400 pt")
        check(external.callWingWidth(for: .card) == 200 && external.callWingWidth(for: .wings) == 180, "wing per mode")

        // Hover: the compact row while folded, the whole card while open.
        let wings = macbook.hoverRect(expanded: false, callMode: .wings)
        check(wings.width == macbook.callWingsWidth && wings.height == 32, "wings hover the row")
        check(abs(wings.midX - macbook.windowSize.width / 2) < 0.5, "centered")
        let startCard = macbook.hoverRect(expanded: false, callMode: .card)
        check(startCard.height == 32, "the start card hovers only on its row, so it does not grab windows below")
        let open = macbook.hoverRect(expanded: true, callMode: .card)
        check(open.width == macbook.callCardWidth && open.height == macbook.callCardHeight, "the open card hovers whole")
        check(open.contains(CGPoint(x: wings.maxX - 1, y: 16)), "the edge of the wings stays inside the open card")
        check(macbook.hoverRect(expanded: false, callMode: .none) == macbook.hoverRect(expanded: false),
              "without a call, unchanged")
        check(macbook.hoverRect(expanded: true, callMode: .none) == macbook.hoverRect(expanded: true),
              "drawer unchanged")

        // VoiceOver: one sentence per start and per end, however often the state republishes.
        var announcer = CallHUDAnnouncer()
        check(announcer.sentence(for: live) == "Zoom call started.", "start announced")
        check(announcer.sentence(for: live) == nil, "once")
        check(announcer.sentence(for: ended) == "Zoom call ended after 01:00.", "end announced")
        check(announcer.sentence(for: ended) == nil, "once")
        check(announcer.sentence(for: nil) == nil, "clearing says nothing")
        check(announcer.sentence(for: live) == "Zoom call started.", "a new call is announced again")

        if ProcessInfo.processInfo.environment["CALLHUD_RENDER"] != nil {
            // Live samples started 4:27 ago, so the running timer reads as in the design.
            let now = CallHUDPresentation(CallSession(app: app, startedAt: Date() - 267, confirmedAt: Date()))
            let chrome = CallApp(name: "Chrome", bundleID: "com.google.Chrome")
            let meet = CallHUDPresentation(CallSession(app: chrome, startedAt: Date() - 267, confirmedAt: Date()),
                                           service: WebCallService.match(windowTitles: ["Meet - abc"]))
            let faceTime = CallHUDPresentation(CallSession(app: CallAppCatalog.faceTime, startedAt: Date() - 42, confirmedAt: Date()))
            render(layouts: [("macbook", macbook), ("external", external)],
                   samples: [("live-wings", now, NotchCallMode.wings), ("live-card", now, .card), ("ended-card", ended, .card),
                             ("long-wings", CallHUDPresentation(CallSession(app: CallApp(name: "WhatsApp", bundleID: "x"),
                                                                            startedAt: Date() - 3735, confirmedAt: Date())), .wings),
                             ("meet-card", meet, .card), ("meet-wings", meet, .wings), ("facetime-wings", faceTime, .wings)])
        }
        print("PASS: CallHUDViewProbe verified")
    }

    /// The notch as NotchView draws it during a call, with the camera housing on top.
    struct Preview: View {
        let layout: NotchLayout
        let call: CallHUDPresentation
        let mode: NotchCallMode

        var body: some View {
            let width = layout.callRowWidth(for: mode)
            let isCard = mode == .card
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.09, green: 0.14, blue: 0.25), Color(red: 0.36, green: 0.18, blue: 0.33)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    CallHUDRow(presentation: call, mode: mode, wingWidth: layout.callWingWidth(for: mode),
                               notchWidth: layout.notchWidth, animated: false)
                        .frame(width: width, height: layout.barHeight)
                    if isCard {
                        CallHUDCardBody(presentation: call, width: width, animated: false)
                    }
                }
                .background(Color.black)
                .clipShape(BottomRoundedRectangle(radius: isCard ? 24 : (layout.hasNotch ? 12 : 14)))
                if layout.hasNotch {
                    // The camera housing has no pixels: anything drawn under it would be lost.
                    // Black for the README images (CALLHUD_DOCS), as the real camera housing looks.
                    Rectangle().fill(ProcessInfo.processInfo.environment["CALLHUD_DOCS"] != nil
                                     ? Color.black : Color.red.opacity(0.35))
                        .frame(width: layout.notchWidth, height: layout.physicalBarHeight)
                }
            }
            .frame(width: layout.windowSize.width, height: layout.callCardHeight + 30)
        }
    }

    static func render(layouts: [(String, NotchLayout)], samples: [(String, CallHUDPresentation, NotchCallMode)]) {
        let directory = URL(fileURLWithPath: "/tmp/callhud")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (screen, layout) in layouts {
            for (name, call, mode) in samples {
                let renderer = ImageRenderer(content: Preview(layout: layout, call: call, mode: mode)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 2
                // App icons can make the renderer pick another color space; convert to sRGB for the PNG.
                guard let raw = renderer.cgImage, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
                      let image = raw.copy(colorSpace: srgb) ?? Optional(raw) else { check(false, "render \(name)"); return }
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                let url = directory.appendingPathComponent("\(screen)-\(name).png")
                check((try? data?.write(to: url)) != nil, "write \(url.path)")
                print("rendered \(url.path)")
            }
        }
    }
}
