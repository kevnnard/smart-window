import AppKit

// Wings HUD (design/notch-system-hud/01-wings.html): geometry, brightness change detection, display
// values and the hide timer.
@main
@MainActor
struct SystemHUDProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        // Geometry: the wings grow sideways around the camera; the window already has room.
        let macBook = NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 280, customHeight: 32)
        check(macBook.hudWingWidth == macBook.wingWidth + NotchLayout.hudWingExtra, "HUD wing adds a fixed extra")
        check(macBook.hudWidth == 185 + macBook.hudWingWidth * 2, "HUD width keeps the camera gap in the middle")
        check(macBook.hudWidth == 388, "HUD on a 280 pt MacBook notch is 388 pt, got \(macBook.hudWidth)")
        check(macBook.windowSize.width >= macBook.hudWidth + NotchLayout.shadowMargin * 2,
              "the fixed window has room for the HUD, got \(macBook.windowSize.width)")
        let hud = macBook.visibleRect(expanded: false, hud: true)
        let compact = macBook.visibleRect(expanded: false)
        check(hud.width == macBook.hudWidth && hud.height == macBook.barHeight, "HUD rect is the wide compact row")
        check(abs(hud.midX - compact.midX) < 0.001, "HUD stays centered on the camera")
        check(macBook.visibleRect(expanded: true, hud: true) == macBook.visibleRect(expanded: true),
              "the open drawer ignores the HUD")
        check(macBook.panelSize(expanded: false, hud: true).width == macBook.hudWidth, "HUD panel width")
        // Content stays inside the wings, clear of the rounded corner and the camera, at any notch size.
        let tight = NotchLayout(notchWidth: 185, physicalBarHeight: 32, customWidth: 180, customHeight: 33)
        for layout in [macBook, tight] {
            let used = NotchLayout.hudEdgeInset + layout.hudLevelBarWidth + NotchLayout.hudLevelSpacing
                + NotchLayout.hudValueWidth + NotchLayout.hudCameraInset
            check(used <= layout.hudWingWidth + 0.001,
                  "level content fits the wing: \(used) <= \(layout.hudWingWidth)")
            check(layout.hudLevelBarWidth >= 40, "the level bar stays readable, got \(layout.hudLevelBarWidth)")
            check(NotchLayout.hudEdgeInset >= 12, "content clears the 12 pt corner radius")
        }
        check(tight.windowSize.width >= tight.hudWidth + NotchLayout.shadowMargin * 2, "tight window fits the HUD")
        let external = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 280, customHeight: 32)
        // A monitor without a camera notch shows the HUD too: the pill grows like the MacBook notch,
        // each half a wing, with no camera gap.
        check(external.hudWingWidth == 140 + NotchLayout.hudWingExtra, "external wing is half the pill plus the extra")
        check(external.hudWidth == external.hudWingWidth * 2, "external HUD has no camera gap")
        check(external.hudWidth == 388, "external 280 pt pill grows to 388 pt, got \(external.hudWidth)")
        check(external.hudLevelBarWidth > 0, "external level bar has room")
        check(external.windowSize.width >= external.hudWidth + NotchLayout.shadowMargin * 2,
              "external window fits the HUD")
        check(external.visibleRect(expanded: false, hud: true).width == external.hudWidth, "external HUD rect")
        let narrow = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 180, customHeight: 30)
        check(narrow.hudWingWidth == 90 + NotchLayout.hudWingExtra && narrow.hudLevelBarWidth >= 40,
              "the narrowest external pill (Settings minimum) still fits a readable bar")

        // Brightness is polled: a key or slider step is a sudden jump; ambient light drifts slowly.
        var detector = BrightnessChangeDetector()
        let t = Date()
        check(!detector.sample(0.65, at: t), "the first reading is not a change")
        check(!detector.sample(0.652, at: t.addingTimeInterval(0.1)), "an ambient drift is ignored")
        check(detector.sample(0.69, at: t.addingTimeInterval(0.2)), "a key step shows the HUD")
        check(detector.sample(0.695, at: t.addingTimeInterval(0.3)), "the rest of the fade keeps updating it")
        check(!detector.sample(0.695, at: t.addingTimeInterval(0.4)), "no change, nothing to show")
        check(!detector.sample(0.697, at: t.addingTimeInterval(3)), "a later drift is ignored again")
        check(detector.sample(0.60, at: t.addingTimeInterval(3.1)), "a step down shows the HUD")
        // A step spread over a fade still counts: movement is measured over the last 0.3 s.
        var fade = BrightnessChangeDetector()
        check(!fade.sample(0.50, at: t), "fade: first reading")
        check(!fade.sample(0.507, at: t.addingTimeInterval(0.1)), "fade: 0.007 alone is not a step yet")
        check(fade.sample(0.514, at: t.addingTimeInterval(0.2)), "fade: 0.014 within 0.2 s is a step")
        // Ambient light drifting slowly never shows it.
        var ambient = BrightnessChangeDetector()
        var ambientShown = false
        for i in 0..<40 {
            ambientShown = ambientShown || ambient.sample(0.5 + Double(i) * 0.002, at: t.addingTimeInterval(Double(i) * 0.1))
        }
        check(!ambientShown, "ambient drift of 0.002 per 0.1 s never shows the HUD")
        // Following lasts 1.6 s from the step, however much drift keeps coming.
        var follow = BrightnessChangeDetector()
        _ = follow.sample(0.5, at: t)
        check(follow.sample(0.56, at: t.addingTimeInterval(0.1)), "follow: step")
        check(follow.sample(0.561, at: t.addingTimeInterval(1.0)), "follow: drift within 1.6 s updates")
        check(follow.sample(0.562, at: t.addingTimeInterval(1.5)), "follow: still within 1.6 s")
        check(!follow.sample(0.563, at: t.addingTimeInterval(1.8)), "follow: drift does not extend the window")

        // What each wing shows.
        let muted = SystemHUDEvent(kind: .volume, level: 0.62, muted: true)
        check(muted.symbolName == "speaker.slash.fill" && muted.valueText == "—" && muted.barFraction == 0,
              "muted volume")
        let silent = SystemHUDEvent(kind: .volume, level: 0, muted: false)
        check(silent.symbolName == "speaker.fill" && silent.valueText == "0", "zero volume")
        let loud = SystemHUDEvent(kind: .volume, level: 0.625, muted: false)
        check(loud.symbolName == "speaker.wave.3.fill" && loud.valueText == "63" && loud.barFraction == 0.625,
              "volume level, got \(loud.valueText)")
        check(SystemHUDEvent(kind: .brightness, level: 0.3, muted: false).symbolName == "sun.min.fill", "dim")
        check(SystemHUDEvent(kind: .brightness, level: 0.8, muted: false).symbolName == "sun.max.fill", "bright")
        check(SystemHUDEvent(kind: .brightness, level: 1.4, muted: false).barFraction == 1, "level is clamped")

        // Timer: hides after the delay; a new change keeps it open.
        let state = SystemHUDState(hideDelay: 0.08)
        check(state.event == nil, "starts hidden")
        state.show(loud)
        check(state.event == loud, "shows the event")
        wait(0.05)
        state.show(silent)
        wait(0.05)
        check(state.event == silent, "a new change restarts the timer")
        wait(0.08)
        check(state.event == nil, "hides after the delay")

        print("PASS: SystemHUDProbe verified")
    }

    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
