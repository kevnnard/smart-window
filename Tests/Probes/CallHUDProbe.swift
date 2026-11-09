import Foundation

// Call HUD (design/notch-call-hud/03-call-card.html): which processes are calls, the call tracker,
// timer text, when the card shows, the screen reader sentences and the mic level mapping.
@main
@MainActor
struct CallHUDProbe {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    static func main() {
        catalog()
        tracker()
        timerText()
        cardRule()
        sentences()
        micLevel()
        state()
        webService()
        print("PASS: CallHUDProbe verified")
    }

    static func proc(_ bundle: String?, _ exe: String? = nil, pid: pid_t = 100, input: Bool = true) -> AudioInputProcess {
        AudioInputProcess(pid: pid, bundleID: bundle, executable: exe, isRunningInput: input)
    }

    static func catalog() {
        check(CallAppCatalog.match(bundleID: "us.zoom.xos", executable: nil)?.name == "Zoom", "Zoom is a call app")
        check(CallAppCatalog.match(bundleID: "com.google.Chrome.helper", executable: nil)?.name == "Chrome",
              "a browser helper counts as its browser")
        check(CallAppCatalog.match(bundleID: "company.thebrowser.browser.helper", executable: "Browser Helper")?.name == "Arc",
              "bundle IDs match whatever their case (Arc's helper reports lowercase)")
        check(CallAppCatalog.match(bundleID: "company.thebrowser.dia", executable: "Dia")?.name == "Dia", "Dia is a browser")
        check(CallAppCatalog.match(bundleID: "com.apple.avconferenced", executable: "avconferenced")?.name == "FaceTime",
              "avconferenced as CoreAudio reports it")
        check(CallAppCatalog.match(bundleID: "com.google.Chromeish", executable: nil) == nil,
              "a prefix must end at a dot")
        let facetime = CallAppCatalog.match(bundleID: nil, executable: "avconferenced")
        check(facetime?.name == "FaceTime" && facetime?.bundleID == "com.apple.FaceTime",
              "FaceTime's audio daemon is FaceTime")
        check(CallAppCatalog.match(bundleID: "com.apple.VoiceMemos", executable: "VoiceMemos") == nil,
              "Voice Memos is not a call")
        check(CallAppCatalog.match(bundleID: nil, executable: nil) == nil, "unknown process is not a call")

        let own: pid_t = 42
        let processes = [
            proc("com.apple.VoiceMemos", pid: 1),
            proc("us.zoom.xos", pid: 2, input: false),
            proc("net.whatsapp.WhatsApp", pid: 3),
            proc("com.kevnnard.smartwindow", pid: own),
            proc("com.google.Chrome.helper", pid: 5),
            proc("com.google.Chrome.helper", pid: 6),
        ]
        let active = CallAppCatalog.activeCalls(in: processes, excluding: own)
        check(active.map(\.name) == ["WhatsApp", "Chrome"],
              "only call apps with running input, own process excluded, one entry per app: \(active.map(\.name))")
        check(CallAppCatalog.activeCalls(in: [proc("us.zoom.xos", pid: own)], excluding: own).isEmpty,
              "SmartWindow's own mic use never counts")
    }

    static func tracker() {
        let zoom = CallApp(name: "Zoom", bundleID: "us.zoom.xos")
        let meet = CallApp(name: "Chrome", bundleID: "com.google.Chrome")
        let t0 = Date(timeIntervalSince1970: 1_000)
        var tracker = CallTracker()

        check(tracker.update(active: [zoom], at: t0) == nil && tracker.session == nil, "a brief mic use is not a call yet")
        check(tracker.update(active: [], at: t0 + 0.5) == nil && tracker.session == nil, "mic released before confirm: no call")
        check(tracker.update(active: [zoom], at: t0 + 1) == nil, "candidate restarts")
        let started = tracker.update(active: [zoom], at: t0 + 2)
        check(started == .started && tracker.session?.app == zoom, "input held for the confirm delay starts the call")
        check(tracker.session?.startedAt == t0 + 1, "the call is timed from the first detection")
        check(tracker.session?.confirmedAt == t0 + 2, "the confirmation time drives the start card")

        check(tracker.update(active: [], at: t0 + 3) == nil && tracker.session?.endedAt == nil,
              "a short gap does not end the call")
        check(tracker.update(active: [zoom], at: t0 + 4) == nil, "the call continues")
        check(tracker.update(active: [meet], at: t0 + 5) == nil && tracker.session?.app == meet,
              "when the app changes the call keeps going under the app now holding the mic")
        check(tracker.session?.startedAt == t0 + 1, "the timer does not restart")
        check(tracker.update(active: [zoom, meet], at: t0 + 6) == nil && tracker.session?.app == meet,
              "a second app does not take the call over")

        check(tracker.update(active: [], at: t0 + 7) == nil, "grace period")
        let ended = tracker.update(active: [], at: t0 + 8.5)
        check(ended == .ended, "no call app for the grace delay ends the call")
        check(tracker.session?.endedAt == t0 + 6, "the call ends when the mic was last seen")
        check(tracker.session.map { $0.duration } == 5, "duration is end minus start")
        check(tracker.update(active: [], at: t0 + 10) == nil, "the ended card stays")
        check(tracker.update(active: [], at: t0 + 11.1) == .cleared && tracker.session == nil,
              "the ended card clears after 2.5 s")

        // A new call during the ended card replaces it once confirmed.
        var again = CallTracker()
        _ = again.update(active: [zoom], at: t0)
        _ = again.update(active: [zoom], at: t0 + 1)
        _ = again.update(active: [], at: t0 + 3.5)
        check(again.session?.endedAt != nil, "ended")
        check(again.update(active: [meet], at: t0 + 4) == nil && again.session?.endedAt != nil,
              "a new call needs its own confirmation")
        check(again.update(active: [meet], at: t0 + 5) == .started && again.session?.app == meet
              && again.session?.endedAt == nil, "a confirmed new call replaces the ended card")
    }

    static func timerText() {
        check(CallHUDPresentation.timerText(0) == "00:00", "zero")
        check(CallHUDPresentation.timerText(2.9) == "00:02", "seconds round down")
        check(CallHUDPresentation.timerText(267) == "04:27", "minutes")
        check(CallHUDPresentation.timerText(3599) == "59:59", "under an hour")
        check(CallHUDPresentation.timerText(3735) == "1:02:15", "hours appear only when needed")
        check(CallHUDPresentation.timerText(-5) == "00:00", "never negative")
    }

    static func cardRule() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        let app = CallApp(name: "FaceTime", bundleID: "com.apple.FaceTime")
        let live = CallHUDPresentation(CallSession(app: app, startedAt: t0 - 1, confirmedAt: t0))
        check(live.phase == .live, "live")
        check(live.showsCard(at: t0 + 2.9, hovering: false), "the card shows for 3 s after the call starts")
        check(!live.showsCard(at: t0 + 3, hovering: false), "then it folds into wings")
        check(live.showsCard(at: t0 + 60, hovering: true), "hovering brings the card back")
        check(live.timer(at: t0 + 266) == "04:27", "the timer counts from the start")

        var session = CallSession(app: app, startedAt: t0, confirmedAt: t0 + 1)
        session.endedAt = t0 + 724
        let ended = CallHUDPresentation(session)
        check(ended.phase == .ended && ended.showsCard(at: t0 + 9_999, hovering: false), "the ended card always shows")
        check(ended.timer(at: t0 + 9_999) == "12:04", "the ended card shows the total, frozen")
    }

    static func sentences() {
        let t0 = Date(timeIntervalSince1970: 3_000)
        let app = CallApp(name: "Zoom", bundleID: "us.zoom.xos")
        var session = CallSession(app: app, startedAt: t0, confirmedAt: t0)
        check(CallHUDPresentation(session).sentence == "Zoom call started.", "start sentence")
        session.endedAt = t0 + 724
        check(CallHUDPresentation(session).sentence == "Zoom call ended after 12:04.", "end sentence")
    }

    static func micLevel() {
        check(MicLevel.normalized(rms: 0) == 0, "silence is zero")
        check(MicLevel.normalized(rms: 1) == 1, "full scale is one")
        check(MicLevel.normalized(rms: 0.001) == 0, "-60 dB is below the floor")
        let speech = MicLevel.normalized(rms: 0.05)
        check(speech > 0.4 && speech < 0.9, "speech around -26 dB lands mid-range: \(speech)")
        check(MicLevel.normalized(rms: .nan) == 0, "NaN is silence")
        let bars = MicLevel.barHeights(level: 1, count: 7, maxHeight: 16, minHeight: 3, seed: 0)
        check(bars.count == 7 && bars.allSatisfy { $0 >= 3 && $0 <= 16 }, "bars stay inside min and max")
        let quiet = MicLevel.barHeights(level: 0, count: 24, maxHeight: 38, minHeight: 3, seed: 5)
        check(quiet.allSatisfy { $0 == 3 }, "silence rests as dots")
        let loud = MicLevel.barHeights(level: 1, count: 24, maxHeight: 38, minHeight: 3, seed: 5)
        check(loud[11] > loud[0], "the middle bars are taller than the edges")
    }

    static func state() {
        let t0 = Date(timeIntervalSince1970: 4_000)
        let app = CallApp(name: "Zoom", bundleID: "us.zoom.xos")
        let callState = CallHUDState()
        check(callState.presentation == nil && !callState.isActive, "idle")
        callState.update(session: CallSession(app: app, startedAt: t0, confirmedAt: t0))
        check(callState.isActive && callState.presentation?.phase == .live, "live call published")
        var ended = CallSession(app: app, startedAt: t0, confirmedAt: t0)
        ended.endedAt = t0 + 5
        callState.update(session: ended)
        check(callState.isActive && callState.presentation?.phase == .ended, "ended card is still active")
        callState.update(session: nil)
        check(!callState.isActive && callState.presentation == nil, "cleared")
    }

    static func webService() {
        let chrome = CallAppCatalog.match(bundleID: "com.google.Chrome.helper", executable: nil)!
        check(chrome.isBrowser && chrome.bundleID == "com.google.Chrome", "a browser helper is the browser")
        check(!CallAppCatalog.match(bundleID: "us.zoom.xos", executable: nil)!.isBrowser, "Zoom is not a browser")
        check(CallAppCatalog.match(bundleID: "com.apple.WebKit.GPU", executable: nil)!.isBrowser, "Safari's GPU process")

        // The service comes from the browser window titles, front window first.
        check(WebCallService.match(windowTitles: ["Meet - abc-defg-hij - Google Chrome"])?.name == "Google Meet", "Meet title")
        check(WebCallService.match(windowTitles: ["Inbox", "Meet – Weekly sync"])?.name == "Google Meet", "Meet in a second window")
        check(WebCallService.match(windowTitles: ["Chat | Microsoft Teams"])?.name == "Teams", "Teams")
        check(WebCallService.match(windowTitles: ["Zoom Meeting"])?.name == "Zoom", "Zoom web client")
        check(WebCallService.match(windowTitles: ["Webex Meetings"])?.name == "Webex", "Webex")
        check(WebCallService.match(windowTitles: ["(3) WhatsApp"])?.name == "WhatsApp", "WhatsApp Web")
        check(WebCallService.match(windowTitles: ["Slack | huddle"])?.name == "Slack", "Slack huddle")
        check(WebCallService.match(windowTitles: ["Discord | #general"])?.name == "Discord", "Discord")
        check(WebCallService.match(windowTitles: ["How to zoom a photo - Google Search", "Meeting notes"]) == nil,
              "words like zoom or meeting alone are not a call service")
        check(WebCallService.match(windowTitles: []) == nil, "no windows (no Accessibility) is no service")
        check(WebCallService.match(windowTitles: ["How to meet - Google Search"]) == nil, "meet - inside a search is not Meet")
        check(WebCallService.match(windowTitles: ["WhatsApp privacy documentation"]) == nil, "a page about WhatsApp is not WhatsApp Web")
        check(WebCallService.match(windowTitles: ["WhatsApp Web"])?.name == "WhatsApp", "WhatsApp Web")
        check(WebCallService.match(windowTitles: ["Google Meet alternatives - Google Search"]) == nil, "a search about Meet")
        check(WebCallService.match(windowTitles: ["(Draft) Meet - notes"]) == nil, "only a numeric unread counter is stripped")
        check(WebCallService.match(windowTitles: ["Google Meet"])?.name == "Google Meet", "Meet home")
        check(WebCallService.match(windowTitles: ["Meet - x", "Zoom Meeting"])?.name == "Google Meet", "front window wins")

        // The presentation names the service and the browser.
        let t0 = Date(timeIntervalSince1970: 9_000)
        let session = CallSession(app: chrome, startedAt: t0, confirmedAt: t0)
        let meet = WebCallService.match(windowTitles: ["Meet - x"])!
        let viaMeet = CallHUDPresentation(session, service: meet)
        check(viaMeet.title == "Google Meet" && viaMeet.via == "Chrome", "title Google Meet, via Chrome")
        check(viaMeet.sentence == "Google Meet call started.", "VoiceOver names the service")
        let plain = CallHUDPresentation(session)
        check(plain.title == "Chrome" && plain.via == nil && plain.sentence == "Chrome call started.", "unknown site keeps the browser")
        let zoom = CallHUDPresentation(CallSession(app: CallApp(name: "Zoom", bundleID: "us.zoom.xos"), startedAt: t0, confirmedAt: t0),
                                       service: meet)
        check(zoom.title == "Zoom" && zoom.via == nil, "a native app ignores any web service")

        // Once found, the service sticks for the call (switching tabs hides it from the title),
        // a different service replaces it, and a new call starts over.
        var resolver = WebCallServiceResolver()
        let safari = CallAppCatalog.match(bundleID: "com.apple.Safari", executable: nil)!
        check(resolver.resolve(confirmedAt: t0, app: chrome, matched: nil) == nil, "nothing yet")
        check(resolver.resolve(confirmedAt: t0, app: chrome, matched: meet)?.name == "Google Meet", "found")
        check(resolver.resolve(confirmedAt: t0, app: chrome, matched: nil)?.name == "Google Meet", "sticks after a tab switch")
        let teams = WebCallService.match(windowTitles: ["Microsoft Teams"])!
        check(resolver.resolve(confirmedAt: t0, app: chrome, matched: teams)?.name == "Teams", "another service replaces it")
        check(resolver.resolve(confirmedAt: t0, app: safari, matched: nil) == nil, "the call moving to another browser starts over")
        check(resolver.resolve(confirmedAt: t0 + 60, app: safari, matched: nil) == nil, "a new call starts over")
        var hop = WebCallServiceResolver()
        _ = hop.resolve(confirmedAt: t0, app: chrome, matched: meet)
        _ = hop.resolve(confirmedAt: t0, app: CallApp(name: "Zoom", bundleID: "us.zoom.xos"), matched: nil)
        check(hop.resolve(confirmedAt: t0, app: chrome, matched: nil) == nil, "Chrome/Meet -> Zoom -> Chrome does not bring Meet back")

        // The titles read are those of the browser holding the call, not of another browser also using input.
        check(CallMonitorService.titleSource(tracked: safari, active: [chrome, safari]) == safari, "the tracked browser")
        check(CallMonitorService.titleSource(tracked: nil, active: [chrome, safari]) == chrome, "before the call: the first browser")
        check(CallMonitorService.titleSource(tracked: safari, active: [chrome]) == chrome, "tracked browser gone: the active one")
        let zoomApp = CallApp(name: "Zoom", bundleID: "us.zoom.xos")
        check(CallMonitorService.titleSource(tracked: zoomApp, active: [zoomApp, chrome]) == nil, "a native call reads no titles")
        check(CallMonitorService.titleSource(tracked: nil, active: [zoomApp, chrome]) == nil,
              "the call about to start is native (the tracker takes the first app): no titles")

        // The state publishes the service.
        let callState = CallHUDState()
        callState.update(session: session, service: meet)
        check(callState.presentation?.title == "Google Meet", "state keeps the service")
    }
}
