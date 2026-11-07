import Foundation

@main struct NotchSettingsProbe {
    static func main() {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() {
                fputs("FAIL: \(name)\n", stderr)
                exit(1)
            }
        }

        // Test constants
        check(AppSettings.notchMinWidth == 180.0, "notchMinWidth is 180")
        check(AppSettings.notchMaxWidth == 440.0, "notchMaxWidth is 440")
        check(AppSettings.notchMinHeight == 30.0, "notchMinHeight is 30")
        check(AppSettings.notchMaxHeight == 46.0, "notchMaxHeight is 46")
        check(DisplayPreferences.NotchSize.widthRange == AppSettings.notchMinWidth...AppSettings.notchMaxWidth
              && DisplayPreferences.NotchSize.heightRange == AppSettings.notchMinHeight...AppSettings.notchMaxHeight,
              "per-display notch size ranges match the global sliders")
        check(AppSettings.notchDefaultWidth == 280.0, "notchDefaultWidth is 280")
        check(AppSettings.notchDefaultHeight == 34.0, "notchDefaultHeight is 34")

        // Test NotchLayout logic
        let nonNotchedLayout = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 280, customHeight: 34)
        check(!nonNotchedLayout.hasNotch, "non-notched hasNotch is false")
        check(nonNotchedLayout.contentWidth == 280, "non-notched contentWidth matches customWidth")
        check(nonNotchedLayout.barHeight == 34, "non-notched barHeight matches customHeight")
        check(nonNotchedLayout.panelSize.width == 280, "panelSize width matches contentWidth")
        check(nonNotchedLayout.panelSize.height == 34 + NotchLayout.bottomPadding, "panelSize height includes bottom padding")

        // Test custom dimensions on non-notched layout
        let customNonNotched = NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 350, customHeight: 40)
        check(customNonNotched.contentWidth == 350, "custom width respected")
        check(customNonNotched.barHeight == 40, "custom height respected")

        // Test notched screen layout
        let notchedLayout = NotchLayout(notchWidth: 180, physicalBarHeight: 38, customWidth: 280, customHeight: 34)
        check(notchedLayout.hasNotch, "notched hasNotch is true")
        // On a notched screen the width is the total width, camera notch included.
        check(abs(notchedLayout.wingWidth - 50) < 0.01, "wings take what is left beside the notch")
        check(abs(notchedLayout.contentWidth - 280) < 0.01, "notched content width equals the configured width")
        let tightest = NotchLayout(notchWidth: 185, physicalBarHeight: 38, customWidth: 180, customHeight: 34)
        check(tightest.wingWidth == NotchLayout.minWingWidth
              && tightest.contentWidth == 185 + 2 * NotchLayout.minWingWidth,
              "minimum width hugs the notch with the smallest wings")
        let widest = NotchLayout(notchWidth: 185, physicalBarHeight: 38, customWidth: 440, customHeight: 34)
        check(abs(widest.wingWidth - 127.5) < 0.01 && abs(widest.contentWidth - 440) < 0.01,
              "maximum width never exceeds the configured width")
        check(!tightest.showsWingText && !tightest.showsSourceLabel, "narrow wings show only icon and indicator")
        check(widest.showsWingText && widest.showsSourceLabel, "wide wings show title and source")
        check(NotchLayout(notchWidth: 0, physicalBarHeight: 34, customWidth: 180, customHeight: 34).showsWingText,
              "screens without a notch always show the title")
        check(notchedLayout.barHeight == 38, "notched barHeight does not shrink below physical inset (38)")

        let customNotched = NotchLayout(notchWidth: 180, physicalBarHeight: 38, customWidth: 280, customHeight: 44)
        check(customNotched.barHeight == 44, "notched barHeight expands when customHeight > physicalBarHeight")

        // Panel sizing shared by NotchView and NotchController
        check(nonNotchedLayout.panelSize(expanded: false) == nonNotchedLayout.panelSize, "compact panelSize(expanded:) matches panelSize")
        // The expanded card keeps the compact width and grows down; a narrow card stacks its header.
        let expandedSmall = nonNotchedLayout.panelSize(expanded: true)
        check(expandedSmall.width == 280, "expanded width defaults to the compact width")
        check(nonNotchedLayout.stacksExpandedHeader, "a narrow card stacks its header")
        check(expandedSmall.height == NotchLayout.expandedStackedCardHeight + NotchLayout.bottomPadding,
              "a stacked card is taller")
        check(nonNotchedLayout.expandedTopInset == 0, "cards on screens without a notch start at the top edge")
        var wider = nonNotchedLayout
        wider.expandedExtraWidth = 200
        check(wider.panelSize(expanded: true).width == 480 && !wider.stacksExpandedHeader,
              "Expanded width adds to the compact width")
        check(wider.panelSize(expanded: true).height == NotchLayout.expandedCardHeight + NotchLayout.bottomPadding,
              "a wide card keeps the one-row header height")
        // On a MacBook the card grows down from the notch: the camera band stays empty on top.
        let macBook = NotchLayout(notchWidth: 185, physicalBarHeight: 38, customWidth: 280, customHeight: 34)
        check(macBook.expandedTopInset == 38, "cards on a notched screen reserve the notch band")
        check(macBook.panelSize(expanded: true).height == 38 + NotchLayout.expandedStackedCardHeight + NotchLayout.bottomPadding,
              "notched expanded height adds the notch band above the card content")
        let hugging = NotchLayout(notchWidth: 185, physicalBarHeight: 38, customWidth: 180, customHeight: 34)
        check(hugging.panelSize(expanded: true).width == NotchLayout.expandedMinWidth,
              "a notch too small for the content widens only to the content minimum")
        check(NotchLayout.expandedCardHeight == 180, "expanded card height is 180")
        let wide = NotchLayout(notchWidth: 400, physicalBarHeight: 38, customWidth: 440, customHeight: 34)
        check(wide.contentWidth > 440, "wide layout content is wider than 440")
        check(wide.panelSize(expanded: true).width == wide.contentWidth, "expanded width never below contentWidth")
        check(AppSettings.notchExpandedExtraWidthRange == 0...200, "Expanded width setting adds 0-200 pt")
        check(wide.panelSize(expanded: true).width >= wide.panelSize(expanded: false).width, "expanded never narrower than compact")

        // Visible source badges always include the main source
        func source(_ id: String, active: Bool = false) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: active)
        }
        let few = [source("a", active: true), source("b"), source("c")]
        check(NotchView.visibleSources(few, max: 3).map(\.id) == ["a", "b", "c"], "list of 3 unchanged")
        let two = [source("a"), source("b", active: true)]
        check(NotchView.visibleSources(two, max: 3).map(\.id) == ["a", "b"], "list of 2 unchanged")
        let inside = [source("a"), source("b", active: true), source("c"), source("d")]
        check(NotchView.visibleSources(inside, max: 3).map(\.id) == ["a", "b", "c"], "active within first 3 keeps order")
        let beyond = [source("a"), source("b"), source("c"), source("d", active: true), source("e")]
        let visible = NotchView.visibleSources(beyond, max: 3).map(\.id)
        check(visible == ["d", "a", "b"], "active beyond index 2 is moved first into the visible set")
        check(visible.count == 3, "visible set never exceeds max")
        let noneActive = [source("a"), source("b"), source("c"), source("d")]
        check(NotchView.visibleSources(noneActive, max: 3).map(\.id) == ["a", "b", "c"], "no active source keeps first 3")

        // Progress position: interpolated while playing, frozen while paused, clamped, nil when unknown
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        check(NotchProgress.position(elapsed: 60, timestamp: t0, rate: 1, duration: 240, now: t0.addingTimeInterval(5)) == 65,
              "playing position interpolates from the timestamp")
        check(NotchProgress.position(elapsed: 60, timestamp: t0, rate: 2, duration: 240, now: t0.addingTimeInterval(5)) == 70,
              "playing position scales with the playback rate")
        check(NotchProgress.position(elapsed: 60, timestamp: t0, rate: 0, duration: 240, now: t0.addingTimeInterval(30)) == 60,
              "paused position stays frozen")
        check(NotchProgress.position(elapsed: 230, timestamp: t0, rate: 1, duration: 240, now: t0.addingTimeInterval(60)) == 240,
              "position is clamped to duration")
        check(NotchProgress.position(elapsed: 60, timestamp: nil, rate: 1, duration: 240, now: t0) == 60,
              "missing timestamp uses elapsed as is")
        check(NotchProgress.position(elapsed: 60, timestamp: t0, rate: 1, duration: nil, now: t0) == nil,
              "nil when duration is unknown")
        check(NotchProgress.position(elapsed: 60, timestamp: t0, rate: 1, duration: 0, now: t0) == nil,
              "nil when duration is zero")
        check(NotchProgress.position(elapsed: nil, timestamp: t0, rate: 1, duration: 240, now: t0) == nil,
              "nil when elapsed is unknown")

        // Time format: m:ss, or h:mm:ss from one hour
        check(NotchProgress.format(0) == "0:00", "format 0 is 0:00")
        check(NotchProgress.format(65) == "1:05", "format 65 is 1:05")
        check(NotchProgress.format(3725) == "1:02:05", "format 3725 is 1:02:05")
        check(NotchProgress.format(59.9) == "0:59", "format truncates fractional seconds")
        check(NotchProgress.format(-3) == "0:00", "format never shows negative time")

        // Card copy: only reported metadata
        check(NotchView.subtitle(artist: "A", album: "B") == "A — B", "subtitle joins artist and album")
        check(NotchView.subtitle(artist: "A", album: "") == "A", "subtitle is artist alone")
        check(NotchView.subtitle(artist: "", album: "B") == "B", "subtitle is album alone")
        check(NotchView.subtitle(artist: "", album: "") == nil, "no subtitle without metadata")

        // Control status under the transport buttons
        let errorStatus = NotchView.controlStatus(error: "E", canControl: false, reason: "R")
        check(errorStatus?.text == "E" && errorStatus?.isError == true, "command error replaces the reason")
        let reasonStatus = NotchView.controlStatus(error: nil, canControl: false, reason: "R")
        check(reasonStatus?.text == "R" && reasonStatus?.isError == false, "reason shown when controls are disabled")
        check(NotchView.controlStatus(error: nil, canControl: true, reason: "R") == nil, "no status when controllable")
        check(NotchView.controlStatus(error: nil, canControl: false, reason: nil) == nil, "no status without a reason")

        print("PASS: NotchSettingsProbe verified")
    }
}
