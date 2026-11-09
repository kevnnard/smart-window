import Foundation

// Call HUD (design/notch-call-hud/03-call-card.html): a call is a known call app holding the
// microphone input. The notch shows a card when it starts, wings while it lasts, and a card with the
// total when it ends.

/// An app that can hold a call, named as the notch shows it.
struct CallApp: Equatable, Hashable {
    let name: String
    /// The app whose icon is shown (FaceTime for its audio daemon, the browser for its helpers).
    let bundleID: String

    /// A browser: the call is a web call, named by the browser window title when it can be.
    var isBrowser: Bool { CallAppCatalog.browserBundleIDs.contains(bundleID) }
}

/// A call service running in a browser tab, recognized by the browser window title.
struct WebCallService: Equatable {
    let name: String
    /// Installed apps of the same service whose icon stands for it (Meet has none).
    let iconBundleIDs: [String]

    /// How a window title names a service, lowercased: `starts` is the service name at the start of
    /// the title, followed by its end or a separator (so "WhatsApp privacy" is not WhatsApp Web);
    /// `contains` are strings only the service's own page has. Plain words like "zoom" or "meet" are
    /// not enough.
    struct Pattern {
        var starts: [String] = []
        var contains: [String] = []
    }

    static let all: [(service: WebCallService, pattern: Pattern)] = [
        (WebCallService(name: "Google Meet", iconBundleIDs: []),
         Pattern(starts: ["meet", "google meet"], contains: ["meet.google.com"])),
        (WebCallService(name: "Teams", iconBundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"]),
         Pattern(starts: ["microsoft teams"], contains: ["| microsoft teams", "microsoft teams |", "teams.microsoft.com", "teams.live.com"])),
        (WebCallService(name: "Zoom", iconBundleIDs: ["us.zoom.xos"]),
         Pattern(starts: ["zoom meeting", "zoom workplace"], contains: ["app.zoom.us", "zoom.us/wc"])),
        (WebCallService(name: "Webex", iconBundleIDs: ["Cisco-Systems.Spark", "com.webex.meetingmanager"]),
         Pattern(starts: ["webex"], contains: ["webex.com"])),
        (WebCallService(name: "WhatsApp", iconBundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
         Pattern(starts: ["whatsapp"], contains: ["web.whatsapp.com"])),
        (WebCallService(name: "Slack", iconBundleIDs: ["com.tinyspeck.slackmacgap"]), Pattern(starts: ["slack"])),
        (WebCallService(name: "Discord", iconBundleIDs: ["com.hnc.Discord"]), Pattern(starts: ["discord"])),
        (WebCallService(name: "Jitsi Meet", iconBundleIDs: []), Pattern(starts: ["jitsi meet"], contains: ["meet.jit.si"])),
    ]

    /// After a name at the start of a title, one of these (or the end) must follow.
    private static let separators = [" - ", " – ", " | ", " · ", " web", " meetings", " meeting", ": "]

    /// The service in the first window whose title names one (front window first). Only the active
    /// tab of each window is in its title.
    static func match(windowTitles: [String]) -> WebCallService? {
        for title in windowTitles.map(normalized) {
            for entry in all where names(entry.pattern, title) {
                return entry.service
            }
        }
        return nil
    }

    private static func names(_ pattern: Pattern, _ title: String) -> Bool {
        if pattern.contains.contains(where: title.contains) { return true }
        return pattern.starts.contains { name in
            guard title.hasPrefix(name) else { return false }
            let rest = title.dropFirst(name.count)
            return rest.isEmpty || separators.contains { rest.hasPrefix($0) }
        }
    }

    /// Lowercased, without an unread counter such as "(3) " (numbers only).
    private static func normalized(_ title: String) -> String {
        let title = title.lowercased().trimmingCharacters(in: .whitespaces)
        guard title.hasPrefix("("), let close = title.firstIndex(of: ")"),
              title[title.index(after: title.startIndex)..<close].allSatisfy(\.isNumber),
              title.index(after: title.startIndex) < close else { return title }
        return String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
    }
}

/// Keeps the web service of a call once found: switching tabs takes it out of the title, but the
/// call is still on it. A different service replaces it; a new call, or the call moving to another
/// app, starts over.
struct WebCallServiceResolver {
    private var key: (confirmedAt: Date, bundleID: String)?
    private var service: WebCallService?

    mutating func resolve(confirmedAt: Date, app: CallApp, matched: WebCallService?) -> WebCallService? {
        if key?.confirmedAt != confirmedAt || key?.bundleID != app.bundleID {
            key = (confirmedAt, app.bundleID)
            service = nil
        }
        if let matched { service = matched }
        return service
    }
}

/// One process using audio, as CoreAudio reports it.
struct AudioInputProcess: Equatable {
    let pid: pid_t
    let bundleID: String?
    /// Executable name, for daemons without a bundle ID.
    let executable: String?
    /// The process is capturing from an input device.
    let isRunningInput: Bool
}

/// Which processes are calls. Any other app using the microphone (dictation, Voice Memos, a
/// recorder) is not a call.
enum CallAppCatalog {
    static let faceTime = CallApp(name: "FaceTime", bundleID: "com.apple.FaceTime")

    /// A process matches when its bundle ID equals one of these or starts with it plus "." (helpers
    /// such as com.google.Chrome.helper), ignoring case: Arc's helper reports
    /// company.thebrowser.browser.helper. Browsers count for Meet and other web calls.
    static let apps: [(bundleID: String, app: CallApp)] = {
        func app(_ name: String, _ id: String, also: [String] = []) -> [(String, CallApp)] {
            let entry = CallApp(name: name, bundleID: id)
            return ([id] + also).map { ($0, entry) }
        }
        return [("com.apple.FaceTime", faceTime)]
            + app("Zoom", "us.zoom.xos")
            + app("Teams", "com.microsoft.teams2", also: ["com.microsoft.teams"])
            + app("WhatsApp", "net.whatsapp.WhatsApp", also: ["desktop.WhatsApp"])
            + app("Discord", "com.hnc.Discord")
            + app("Slack", "com.tinyspeck.slackmacgap")
            + app("Webex", "Cisco-Systems.Spark", also: ["com.webex.meetingmanager"])
            + app("Skype", "com.skype.skype")
            + app("Telegram", "ru.keepcoder.Telegram", also: ["org.telegram.desktop"])
            + app("Signal", "org.whispersystems.signal-desktop")
            + browsers
    }()

    private static let browserEntries: [(String, String, [String])] = [
        ("Chrome", "com.google.Chrome", []),
        // Safari captures in the WebKit GPU process.
        ("Safari", "com.apple.Safari", ["com.apple.WebKit.GPU"]),
        ("Arc", "company.thebrowser.Browser", []),
        ("Dia", "company.thebrowser.dia", []),
        ("Firefox", "org.mozilla.firefox", []),
        ("Edge", "com.microsoft.edgemac", []),
        ("Brave", "com.brave.Browser", []),
    ]

    private static var browsers: [(bundleID: String, app: CallApp)] {
        browserEntries.flatMap { name, id, also in
            ([id] + also).map { ($0, CallApp(name: name, bundleID: id)) }
        }
    }

    static let browserBundleIDs = Set(browserEntries.map { $0.1 })

    /// FaceTime and iPhone calls relayed to the Mac capture audio in this daemon, not in FaceTime.
    static let daemons: [String: CallApp] = ["avconferenced": faceTime]

    static func match(bundleID: String?, executable: String?) -> CallApp? {
        if let bundleID = bundleID?.lowercased() {
            for entry in apps {
                let id = entry.bundleID.lowercased()
                if bundleID == id || bundleID.hasPrefix(id + ".") { return entry.app }
            }
        }
        return executable.flatMap { daemons[$0] }
    }

    /// Call apps capturing input, in process order, one entry per app. SmartWindow's own process
    /// (the mic meter) never counts.
    static func activeCalls(in processes: [AudioInputProcess], excluding ownPID: pid_t) -> [CallApp] {
        var seen: [CallApp] = []
        for process in processes where process.isRunningInput && process.pid != ownPID {
            if let app = match(bundleID: process.bundleID, executable: process.executable), !seen.contains(app) {
                seen.append(app)
            }
        }
        return seen
    }
}

/// One call: live until `endedAt` is set.
struct CallSession: Equatable {
    var app: CallApp
    /// First time the app was seen capturing; the timer counts from here.
    let startedAt: Date
    /// When the call was confirmed; the start card shows from here.
    let confirmedAt: Date
    /// When the app was last seen capturing, once the call ended.
    var endedAt: Date? = nil

    var duration: TimeInterval { (endedAt ?? startedAt).timeIntervalSince(startedAt) }
}

/// Turns samples of the active call apps (taken about twice a second) into a call that starts,
/// ends and clears. A brief mic use is not a call, and a short gap (an app reopening its input)
/// does not end one.
struct CallTracker {
    /// Input must be held this long before it counts as a call.
    static let confirmDelay: TimeInterval = 1
    /// No call app for this long ends the call.
    static let graceDelay: TimeInterval = 2
    /// How long the ended card shows.
    static let endedDuration: TimeInterval = 2.5

    enum Change: Equatable {
        case started
        case ended
        case cleared
    }

    private(set) var session: CallSession?
    private var candidate: (app: CallApp, since: Date)?
    private var lastSeen: Date?
    private var endedShownAt: Date?

    mutating func update(active: [CallApp], at now: Date) -> Change? {
        if let first = active.first {
            if var live = session, live.endedAt == nil {
                lastSeen = now
                // The call keeps going under the app now holding the mic; a second app does not take over.
                if !active.contains(live.app) {
                    live.app = first
                    session = live
                }
                return nil
            }
            guard let candidate else {
                self.candidate = (first, now)
                return clearEndedIfDue(at: now)
            }
            guard now.timeIntervalSince(candidate.since) >= Self.confirmDelay else {
                return clearEndedIfDue(at: now)
            }
            let app = active.contains(candidate.app) ? candidate.app : first
            session = CallSession(app: app, startedAt: candidate.since, confirmedAt: now)
            self.candidate = nil
            lastSeen = now
            endedShownAt = nil
            return .started
        }

        candidate = nil
        if var live = session, live.endedAt == nil, let lastSeen {
            guard now.timeIntervalSince(lastSeen) >= Self.graceDelay else { return nil }
            live.endedAt = lastSeen
            session = live
            endedShownAt = now
            return .ended
        }
        return clearEndedIfDue(at: now)
    }

    private mutating func clearEndedIfDue(at now: Date) -> Change? {
        guard session?.endedAt != nil, let endedShownAt,
              now.timeIntervalSince(endedShownAt) >= Self.endedDuration else { return nil }
        session = nil
        self.endedShownAt = nil
        return .cleared
    }
}

/// What the notch shows for a call.
struct CallHUDPresentation: Equatable {
    enum Phase: Equatable {
        case live
        case ended
    }

    /// How long the card shows after the call starts before folding into wings.
    static let startCardDuration: TimeInterval = 3

    let session: CallSession
    /// The web service of a browser call, when the window title names one.
    let service: WebCallService?

    init(_ session: CallSession, service: WebCallService? = nil) {
        self.session = session
        self.service = session.app.isBrowser ? service : nil
    }

    var app: CallApp { session.app }
    /// The service of a web call, else the app.
    var title: String { service?.name ?? app.name }
    /// The browser a known web service runs in.
    var via: String? { service == nil ? nil : app.name }
    var phase: Phase { session.endedAt == nil ? .live : .ended }

    /// The card shows when the call starts, when it ends, and while the pointer is on the notch.
    func showsCard(at now: Date, hovering: Bool) -> Bool {
        phase == .ended || hovering || now.timeIntervalSince(session.confirmedAt) < Self.startCardDuration
    }

    /// The running time while live; the total, frozen, once ended.
    func timer(at now: Date) -> String {
        Self.timerText((session.endedAt ?? now).timeIntervalSince(session.startedAt))
    }

    /// "mm:ss" under an hour, "h:mm:ss" from one hour.
    static func timerText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%02d:%02d", minutes, rest)
    }

    /// What VoiceOver says, once per start and end.
    var sentence: String {
        switch phase {
        case .live: return "\(title) call started."
        case .ended: return "\(title) call ended after \(Self.timerText(session.duration))."
        }
    }
}

/// Mic level for the waveform.
enum MicLevel {
    /// Quietest level that moves the bars, and the level that fills them.
    static let floorDecibels: Double = -50
    static let ceilingDecibels: Double = -10

    /// 0...1 from the RMS of a buffer of samples.
    static func normalized(rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(1, max(0, (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)))
    }

    /// Bar heights for a level: taller in the middle, with a jitter that changes with `seed` so the
    /// bars move like a voice. Silence rests as dots.
    static func barHeights(level: Double, count: Int, maxHeight: Double, minHeight: Double, seed: Int) -> [Double] {
        guard count > 0 else { return [] }
        let clamped = min(1, max(0, level))
        let center = Double(count - 1) / 2
        return (0..<count).map { index in
            let distance = center > 0 ? abs(Double(index) - center) / center : 0
            let envelope = 1 - distance * distance * 0.6
            let noise = sin(Double(index) * 12.9898 + Double(seed) * 78.233) * 43758.5453
            let jitter = 0.55 + 0.45 * (noise - noise.rounded(.down))
            let height = minHeight + (maxHeight - minHeight) * clamped * envelope * jitter
            return min(maxHeight, max(minHeight, height))
        }
    }
}

/// The call shown in the notch, on every display.
@MainActor
final class CallHUDState: ObservableObject {
    static let shared = CallHUDState()

    @Published private(set) var presentation: CallHUDPresentation?
    /// The start card shows for 3 s after a call is confirmed.
    @Published private(set) var startCardVisible = false

    private var startCardTimer: Timer?

    var isActive: Bool { presentation != nil }

    func update(session: CallSession?, service: WebCallService? = nil) {
        let previous = presentation?.session
        presentation = session.map { CallHUDPresentation($0, service: service) }
        guard let session, session.endedAt == nil else {
            setStartCard(false)
            return
        }
        if previous?.confirmedAt != session.confirmedAt {
            // A new call restarts the 3 s: the previous call's timer must not fold this card early.
            startCardTimer?.invalidate()
            setStartCard(true)
            let timer = Timer(timeInterval: CallHUDPresentation.startCardDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.setStartCard(false) }
            }
            // Common modes: also fires while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            startCardTimer = timer
        }
    }

    private func setStartCard(_ visible: Bool) {
        if !visible {
            startCardTimer?.invalidate()
            startCardTimer = nil
        }
        if startCardVisible != visible { startCardVisible = visible }
    }
}

/// The microphone level while a call is live, for the waveform. Separate from the call state so 20
/// updates a second redraw only the waveform.
@MainActor
final class MicLevelState: ObservableObject {
    static let shared = MicLevelState()

    /// 0...1.
    @Published var level: Double = 0
    /// The meter is running (Microphone permission granted). Without it the waveform pulses on its own.
    @Published var isMetering = false
}
