import AppKit
import Combine
import Foundation

// MARK: - AudioSourceInfo

public struct AudioSourceInfo: Identifiable, Equatable {
    public let id: String // bundle identifier
    public let name: String
    public let category: String // "spotify", "youtube", "ghostty", "music", "media"
    public let icon: NSImage?
    /// The source is the main one shown in the pill and targeted by the controls.
    public let isActive: Bool
    /// The source reports that it is playing (its media session, else AppleScript for players).
    public let isPlaying: Bool
    /// The source is a macOS Now Playing session, not only a running AppleScript player.
    public let hasSession: Bool

    public init(id: String, name: String, category: String, icon: NSImage?, isActive: Bool, isPlaying: Bool = false,
                hasSession: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.isActive = isActive
        self.isPlaying = isPlaying
        self.hasSession = hasSession
    }

    /// Icons are excluded so polling does not republish when only the NSImage instance differs.
    public static func == (lhs: AudioSourceInfo, rhs: AudioSourceInfo) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.category == rhs.category
            && lhs.isActive == rhs.isActive && lhs.isPlaying == rhs.isPlaying && lhs.hasSession == rhs.hasSession
    }
}

// MARK: - NowPlayingService

/// Shows every media session macOS lists in Now Playing (the media sessions helper) plus running
/// Spotify and Apple Music (AppleScript). While the helper is unavailable the adapter stream supplies
/// the single Now Playing session; without either, only the AppleScript players are shown.
@MainActor
final class NowPlayingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var trackTitle: String = ""
    @Published private(set) var artistName: String = ""
    @Published private(set) var albumName: String = ""
    /// Bundle identifier of the main source, if any (set even while paused).
    @Published private(set) var playerBundleIdentifier: String?
    /// Album artwork from the Now Playing session, or from the player (Spotify), else nil.
    @Published private(set) var artwork: NSImage?
    /// Track duration of the main source, when it reports one.
    @Published private(set) var duration: TimeInterval?
    /// Elapsed time at `elapsedTimestamp`; interpolate with `playbackRate` for live progress.
    @Published private(set) var elapsedTime: TimeInterval?
    @Published private(set) var elapsedTimestamp: Date?
    /// 0 while paused or unknown.
    @Published private(set) var playbackRate: Double = 0
    /// Human-friendly name of the current source app (e.g. "Spotify", "Ghostty", "Chrome").
    @Published private(set) var sourceDisplayName: String = "Spotify"
    /// Category for badge styling: "spotify", "youtube", "ghostty", "music", "media".
    @Published private(set) var sourceCategory: String = "spotify"
    /// Media sources: one per Now Playing session, plus running Spotify/Music without a session.
    @Published private(set) var detectedSources: [AudioSourceInfo] = []
    /// Source chosen by the user; cleared when it is no longer detected, or stops while another source plays.
    @Published private(set) var selectedSourceID: String?
    /// The transport controls can target the main source.
    @Published private(set) var canControl: Bool = false
    /// Why the main source cannot be controlled, when it cannot.
    @Published private(set) var controlUnavailableReason: String?
    /// Whether the selected source has been seen playing since it was selected. A source picked
    /// while paused stays selected until it plays and then stops.
    private var selectionWasPlaying = false

    /// Formatted "Artist — Title" for display in the bar
    var displayText: String {
        guard !trackTitle.isEmpty else { return "" }
        if artistName.isEmpty { return trackTitle }
        return "\(artistName) — \(trackTitle)"
    }

    /// A player is running and reports a track (playing or paused).
    var hasTrack: Bool {
        playerBundleIdentifier != nil && !trackTitle.isEmpty
    }

    /// A player is running at all.
    var hasPlayer: Bool {
        playerBundleIdentifier != nil
    }

    /// Icon of the running player, for the notch badge when no artwork exists.
    var playerIcon: NSImage? {
        guard let id = playerBundleIdentifier else { return nil }
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Actions

    /// Makes the source the main one shown and controlled; the rule in `retainedSelection` keeps or clears it.
    func selectSource(_ id: String) {
        guard let source = detectedSources.first(where: { $0.id == id }) else { return }
        if selectedSourceID != id { selectedSourceID = id }
        selectionWasPlaying = source.isPlaying
        recompute()
    }

    /// Brings the running player to the front. Does nothing when no player is running.
    func openPlayer() {
        guard let id = playerBundleIdentifier else { return }
        openSource(id)
    }

    /// Brings the specified application to the front.
    func openSource(_ bundleIdentifier: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            app.activate()
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Playback controls

    enum TransportAction: String { case previous = "previous track", playPause = "playpause", next = "next track" }
    @Published private(set) var lastCommandError: String?

    enum TransportRoute: Equatable {
        /// The main source is the current Now Playing app: adapter `send`, only while this owner is still current.
        case adapter(expectedOwner: String)
        /// Allowlisted AppleScript command to the player with this bundle id.
        case appleScript(String)
        /// No command can reach only this app.
        case unavailable(String)
    }

    static func unavailableReason(appName: String) -> String {
        "macOS only lets SmartWindow control \(appName) while it is the Mac's current Now Playing app."
    }

    /// The only routes: AppleScript for Spotify/Music, the adapter for the current Now Playing app
    /// (macOS gives no per-session control), and no command for any other app.
    static func route(for bundleIdentifier: String?, current: String?, appName: String) -> TransportRoute? {
        guard let id = bundleIdentifier else { return nil }
        if isPlayer(id) { return .appleScript(id) }
        if id == current { return .adapter(expectedOwner: id) }
        return .unavailable(unavailableReason(appName: appName))
    }

    private func currentRoute() -> TransportRoute? {
        Self.route(for: playerBundleIdentifier, current: currentNowPlayingID, appName: sourceDisplayName)
    }

    func perform(_ action: TransportAction) {
        if lastCommandError != nil { lastCommandError = nil }
        switch currentRoute() {
        case .none:
            lastCommandError = TransportError.noSource.localizedDescription
        case .unavailable(let reason):
            lastCommandError = reason
        case .adapter(let owner):
            adapter.send(action, expectedOwner: owner, appName: Self.displayNameForBundleID(owner)) { [weak self] error in
                if let error { self?.lastCommandError = error.localizedDescription }
            }
        case .appleScript(let id):
            do {
                try sendAppleScript(action, bundleIdentifier: id)
            } catch {
                lastCommandError = error.localizedDescription
            }
        }
    }

    private func sendAppleScript(_ action: TransportAction, bundleIdentifier: String) throws {
        let appName = Self.players.first(where: { $0.bundleIdentifier == bundleIdentifier })?.scriptName ?? bundleIdentifier
        try Self.send(action, bundleIdentifier: bundleIdentifier,
                      runningIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                      execute: { source in
            guard let script = NSAppleScript(source: source) else { throw TransportError.failed }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                throw TransportError.appleScript(appName: appName,
                                                 number: (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue,
                                                 message: error[NSAppleScript.errorMessage] as? String)
            }
        }, refresh: poll)
    }

    enum TransportError: LocalizedError {
        case unavailable, failed, noSource
        case appleScript(appName: String, number: Int?, message: String?)
        var errorDescription: String? {
            switch self {
            case .noSource: return "No audio source is available to control."
            case .unavailable: return "The supported player is no longer running."
            case .failed: return "Could not control the player. Check Automation permission."
            case .appleScript(let appName, let number, let message):
                return NowPlayingService.appleScriptErrorMessage(number: number, message: message, appName: appName)
            }
        }
    }

    /// Names the cause: Automation permission (-1743), app not running (-600), else the system message and number.
    nonisolated static func appleScriptErrorMessage(number: Int?, message: String?, appName: String) -> String {
        switch number {
        case -1743:
            return "SmartWindow is not allowed to control \(appName). Allow it in System Settings > Privacy & Security > Automation."
        case -600:
            return "\(appName) is not running."
        default:
            let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch (text.isEmpty, number) {
            case (false, let number?): return "\(appName): \(text) (error \(number))"
            case (true, let number?): return "Could not control \(appName) (error \(number))."
            case (false, nil): return "\(appName): \(text)"
            case (true, nil): return "Could not control \(appName)."
            }
        }
    }

    static func send(_ action: TransportAction, bundleIdentifier: String?, runningIDs: Set<String>,
                     execute: (String) throws -> Void, refresh: () -> Void) throws {
        guard let id = bundleIdentifier, isPlayer(id), runningIDs.contains(id) else { throw TransportError.unavailable }
        // The ID and command are allowlisted; no track text or external input enters the script.
        let source = """
        if application id "\(id)" is not running then error "Player is no longer running." number -600
        tell application id "\(id)" to \(action.rawValue)
        """
        try execute(source)
        refresh()
    }

    // MARK: - Players

    struct Player {
        let bundleIdentifier: String
        let scriptName: String
        /// AppleScript expression yielding an artwork URL for `t`, or nil when unsupported.
        let artworkExpression: String?
    }

    static let players: [Player] = [
        Player(bundleIdentifier: "com.spotify.client", scriptName: "Spotify", artworkExpression: "artwork url of t"),
        Player(bundleIdentifier: "com.apple.Music", scriptName: "Music", artworkExpression: nil),
    ]

    static func isPlayer(_ bundleIdentifier: String) -> Bool {
        players.contains(where: { $0.bundleIdentifier == bundleIdentifier })
    }

    struct Snapshot: Equatable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var bundleIdentifier: String?
        var artworkURL: URL?
        var artworkData: Data? = nil
        var duration: TimeInterval? = nil
        var elapsedTime: TimeInterval? = nil
        var elapsedTimestamp: Date? = nil
        var playbackRate: Double = 0

        static let idle = Snapshot(isPlaying: false, title: "", artist: "", album: "", bundleIdentifier: nil, artworkURL: nil)
    }

    private enum ArtworkSource: Equatable {
        case none, data(Data), url(URL)
    }

    private let adapter = MediaRemoteAdapterClient.shared
    private let sessionsClient = MediaSessionsClient.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var compiledScripts: [String: NSAppleScript] = [:]
    private let pollInterval: TimeInterval = 2.0
    private var artworkSource: ArtworkSource = .none
    private var artworkTask: Task<Void, Never>?
    private var playerSnapshots: [Snapshot] = []
    /// Sessions from the helper, or the adapter's single session while the helper is unavailable.
    private var sessions: [MediaSession] = []
    /// The Mac's current Now Playing app (owning app), when known.
    private var currentNowPlayingID: String?
    private var candidateSources: [AudioSourceInfo] = []
    private var iconCache: [String: NSImage] = [:]

    init() {
        // Delay start to avoid dispatch_once issues during SwiftUI layout
        DispatchQueue.main.async { [weak self] in
            self?.startPolling()
        }
    }

    deinit {
        pollTimer?.invalidate()
        artworkTask?.cancel()
    }

    // MARK: - Polling

    private func startPolling() {
        sessionsClient.start()
        sessionsClient.$status
            .sink { [weak self] status in
                guard let self else { return }
                // One stream at a time: the adapter stream only while the helper is unavailable.
                if Self.runsAdapterStream(helperStatus: status) { self.adapter.start() } else { self.adapter.stopStream() }
            }
            .store(in: &cancellables)
        sessionsClient.$status
            .combineLatest(sessionsClient.$sessions, sessionsClient.$currentBundleID)
            .combineLatest(adapter.$info, adapter.$adapterAvailable)
            .sink { [weak self] helper, info, adapterAvailable in
                let (status, sessions, current) = helper
                self?.sessionsChanged(Self.effectiveSessions(helperAvailable: status == .available,
                                                             helperSessions: sessions, helperCurrent: current,
                                                             adapterInfo: adapterAvailable ? info : nil))
            }
            .store(in: &cancellables)
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func sessionsChanged(_ input: (sessions: [MediaSession], current: String?)) {
        guard input.sessions != sessions || input.current != currentNowPlayingID else { return }
        sessions = input.sessions
        currentNowPlayingID = input.current
        rebuildSources()
    }

    /// The helper's sessions while it is healthy; otherwise the adapter's single Now Playing
    /// session, which is also the current one; otherwise none (AppleScript players only).
    static func effectiveSessions(helperAvailable: Bool, helperSessions: [MediaSession], helperCurrent: String?,
                                  adapterInfo: NowPlayingInfo?) -> (sessions: [MediaSession], current: String?) {
        if helperAvailable { return (helperSessions, helperCurrent) }
        guard let info = adapterInfo, let session = MediaSession(info: info) else { return ([], nil) }
        return ([session], session.ownerBundleIdentifier)
    }

    /// The adapter stream is the fallback reader: it runs only once the helper is known unavailable,
    /// not while it starts or is healthy.
    static func runsAdapterStream(helperStatus: MediaSessionsClient.Status) -> Bool {
        helperStatus == .unavailable
    }

    /// Skips a poll that starts while another is running. NSAppleScript pumps the run loop while it
    /// waits for a reply, so the poll timer can fire inside `poll()` (a transport command refreshes
    /// through `poll()` too).
    /// A class, not a struct: a mutating method would hold exclusive access to the gate for the
    /// whole body, and a re-entrant check would itself be an exclusivity violation.
    final class PollGate {
        private(set) var isRunning = false

        func run(_ body: () -> Void) -> Bool {
            guard !isRunning else { return false }
            isRunning = true
            defer { isRunning = false }
            body()
            return true
        }
    }

    private let pollGate = PollGate()

    private func poll() {
        _ = pollGate.run {
            // Work on a copy: holding `compiledScripts` inout across AppleScript would make any
            // re-entrant access an exclusivity violation.
            var scripts = compiledScripts
            let snapshots = Self.readPlayerSnapshots(using: &scripts)
            compiledScripts = scripts
            playerSnapshots = snapshots
            rebuildSources()
        }
    }

    private func rebuildSources() {
        candidateSources = Self.mergeSources(sessions: sessions, players: playerSnapshots,
                                             name: Self.displayName(sessions: sessions), icon: icon(for:))
        recompute()
    }

    /// Picks the main source and publishes only the values that changed.
    private func recompute() {
        let retained = Self.retainedSelection(selectedSourceID, selectionWasPlaying: selectionWasPlaying,
                                              sources: candidateSources)
        if retained != selectedSourceID { selectedSourceID = retained }
        if let retained, candidateSources.contains(where: { $0.id == retained && $0.isPlaying }) {
            selectionWasPlaying = true
        } else if retained == nil {
            selectionWasPlaying = false
        }
        let mainID = Self.mainSource(selected: selectedSourceID, selectionWasPlaying: selectionWasPlaying,
                                     sources: candidateSources, current: currentNowPlayingID)
        let sources = candidateSources.map {
            AudioSourceInfo(id: $0.id, name: $0.name, category: $0.category, icon: $0.icon,
                            isActive: $0.id == mainID, isPlaying: $0.isPlaying, hasSession: $0.hasSession)
        }
        if sources != detectedSources { detectedSources = sources }
        let main = sources.first(where: { $0.id == mainID })
        apply(Self.snapshot(for: main, sessions: sessions, players: playerSnapshots), main: main)
    }

    private func apply(_ snapshot: Snapshot, main: AudioSourceInfo?) {
        if snapshot.isPlaying != isPlaying { isPlaying = snapshot.isPlaying }
        if snapshot.title != trackTitle { trackTitle = snapshot.title }
        if snapshot.artist != artistName { artistName = snapshot.artist }
        if snapshot.album != albumName { albumName = snapshot.album }
        if snapshot.bundleIdentifier != playerBundleIdentifier {
            playerBundleIdentifier = snapshot.bundleIdentifier
        }
        if snapshot.duration != duration { duration = snapshot.duration }
        if snapshot.elapsedTime != elapsedTime { elapsedTime = snapshot.elapsedTime }
        if snapshot.elapsedTimestamp != elapsedTimestamp { elapsedTimestamp = snapshot.elapsedTimestamp }
        if snapshot.playbackRate != playbackRate { playbackRate = snapshot.playbackRate }
        let name = main?.name ?? "Spotify"
        let category = main?.category ?? "spotify"
        if name != sourceDisplayName { sourceDisplayName = name }
        if category != sourceCategory { sourceCategory = category }

        let route = currentRoute()
        let controllable: Bool
        let reason: String?
        switch route {
        case .adapter, .appleScript: (controllable, reason) = (true, nil)
        case .unavailable(let text): (controllable, reason) = (false, text)
        case .none: (controllable, reason) = (false, nil)
        }
        if controllable != canControl { canControl = controllable }
        if reason != controlUnavailableReason { controlUnavailableReason = reason }

        let artworkKey: ArtworkSource = snapshot.artworkData.map { .data($0) }
            ?? snapshot.artworkURL.map { .url($0) } ?? .none
        if artworkKey != artworkSource {
            artworkSource = artworkKey
            loadArtwork(artworkKey)
        }
    }

    /// App icons are fetched once per bundle id, not on every update.
    private func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }
        if let icon { iconCache[bundleID] = icon }
        return icon
    }

    // MARK: - Sources

    /// The selection holds while it is detected, unless it was playing, stopped, and another source
    /// now plays; then it is cleared so selection falls back to automatic. A source picked while
    /// paused (`selectionWasPlaying == false`) therefore stays the main source after the click.
    static func retainedSelection(_ selected: String?, selectionWasPlaying: Bool = true,
                                  sources: [AudioSourceInfo]) -> String? {
        guard let selected, let source = sources.first(where: { $0.id == selected }) else { return nil }
        if source.isPlaying || !selectionWasPlaying || !sources.contains(where: \.isPlaying) { return selected }
        return nil
    }

    /// One source per session owner (parent app when set, else the session's bundle id), in the
    /// helper's order, then running AppleScript players without a session. A Spotify or Music with a
    /// session is one source; its playing state comes from the session, with AppleScript as backup.
    /// Apps without a media session never appear.
    static func mergeSources(sessions: [MediaSession], players snapshots: [Snapshot],
                             name: (String) -> String, icon: (String) -> NSImage?) -> [AudioSourceInfo] {
        var sources: [AudioSourceInfo] = []
        for session in sessions {
            let owner = session.ownerBundleIdentifier
            guard !sources.contains(where: { $0.id == owner }) else { continue }
            let shown = mainSession(for: owner, in: sessions)
            let player = snapshots.first(where: { $0.bundleIdentifier == owner })
            let playing = shown?.playing ?? player?.isPlaying ?? false
            sources.append(AudioSourceInfo(id: owner, name: name(owner), category: categoryForBundleID(owner),
                                           icon: icon(owner), isActive: false, isPlaying: playing, hasSession: true))
        }
        for snapshot in snapshots {
            guard let id = snapshot.bundleIdentifier, !sources.contains(where: { $0.id == id }) else { continue }
            sources.append(AudioSourceInfo(id: id, name: name(id), category: categoryForBundleID(id),
                                           icon: icon(id), isActive: false, isPlaying: snapshot.isPlaying))
        }
        return sources
    }

    /// The session shown for an app with several: the first playing one, else the first.
    static func mainSession(for owner: String, in sessions: [MediaSession]) -> MediaSession? {
        let owned = sessions.filter { $0.ownerBundleIdentifier == owner }
        return owned.first(where: { $0.playing == true }) ?? owned.first
    }

    /// Retained selection (see `retainedSelection`); otherwise a playing session (the current Now
    /// Playing app first), the current Now Playing app, a playing AppleScript player, then the first
    /// paused source, or nil (idle).
    static func mainSource(selected: String?, selectionWasPlaying: Bool = true,
                           sources: [AudioSourceInfo], current: String?) -> String? {
        if let selected = retainedSelection(selected, selectionWasPlaying: selectionWasPlaying,
                                            sources: sources) { return selected }
        let playingSessions = sources.filter { $0.hasSession && $0.isPlaying }
        if let current, playingSessions.contains(where: { $0.id == current }) { return current }
        if let first = playingSessions.first { return first.id }
        if let current, sources.contains(where: { $0.id == current }) { return current }
        return sources.first(where: \.isPlaying)?.id ?? sources.first?.id
    }

    /// A source with a session shows the session's metadata and timing, with the AppleScript player
    /// as backup for missing fields; AppleScript players otherwise keep their own metadata. The
    /// playing state always comes from the merged source so the badge and the main display agree.
    static func snapshot(for main: AudioSourceInfo?, sessions: [MediaSession], players snapshots: [Snapshot]) -> Snapshot {
        guard let main else { return .idle }
        let player = snapshots.first(where: { $0.bundleIdentifier == main.id })
        if let session = mainSession(for: main.id, in: sessions) {
            func text(_ value: String, _ backup: String?) -> String { value.isEmpty ? backup ?? "" : value }
            return Snapshot(isPlaying: main.isPlaying,
                            title: text(session.title, player?.title),
                            artist: text(session.artist, player?.artist),
                            album: text(session.album, player?.album),
                            bundleIdentifier: main.id,
                            artworkURL: session.artworkData == nil ? player?.artworkURL : nil,
                            artworkData: session.artworkData,
                            duration: session.duration,
                            elapsedTime: session.elapsedTime,
                            elapsedTimestamp: session.timestamp,
                            playbackRate: main.isPlaying ? session.playbackRate ?? 1 : 0)
        }
        if var player {
            player.isPlaying = main.isPlaying
            return player
        }
        return Snapshot(isPlaying: main.isPlaying, title: "", artist: "", album: "",
                        bundleIdentifier: main.id, artworkURL: nil)
    }

    static func categoryForBundleID(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("spotify") { return "spotify" }
        let browsers = ["chrome", "safari", "browser", "brave", "firefox", "edgemac", "opera", "vivaldi", "zen"]
        if browsers.contains(where: lower.contains) { return "youtube" }
        if lower.contains("ghostty") || lower.contains("terminal") || lower.contains("iterm") { return "ghostty" }
        if lower.contains("music") || lower.contains("podcast") { return "music" }
        return "media"
    }

    /// Names an app by bundle id, using the helper's display name for a session owned by that id
    /// when the system cannot name it.
    static func displayName(sessions: [MediaSession]) -> (String) -> String {
        { id in
            let name = displayNameForBundleID(id)
            guard name == id else { return name }
            return sessions.first(where: { $0.bundleIdentifier == id && $0.parentApplicationBundleIdentifier == nil })?
                .displayName ?? name
        }
    }

    static func displayNameForBundleID(_ id: String) -> String {
        switch id {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Apple Music"
        default:
            if let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName {
                return name
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url.deletingPathExtension().lastPathComponent
            }
            return id
        }
    }

    private func loadArtwork(_ source: ArtworkSource) {
        artworkTask?.cancel()
        artworkTask = nil
        switch source {
        case .none:
            artwork = nil
        case .data(let data):
            artwork = NSImage(data: data)
        case .url(let url):
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      !Task.isCancelled,
                      let image = NSImage(data: data) else { return }
                self?.artwork = image
            }
        }
    }

    // MARK: - AppleScript

    /// Snapshots of running players, playing or paused. Only running players are
    /// queried so AppleScript never launches them.
    static func readPlayerSnapshots(using cache: inout [String: NSAppleScript]) -> [Snapshot] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return players.filter { running.contains($0.bundleIdentifier) }.compactMap { query($0, cache: &cache) }
    }

    private static func query(_ player: Player, cache: inout [String: NSAppleScript]) -> Snapshot? {
        let script: NSAppleScript
        if let cached = cache[player.scriptName] {
            script = cached
        } else {
            let artworkLine = player.artworkExpression.map { "& linefeed & (\($0))" } ?? ""
            let source = """
            tell application "\(player.scriptName)"
                set stateText to "PAUSED"
                if player state is playing then set stateText to "PLAYING"
                try
                    set t to current track
                    return stateText & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) \(artworkLine)
                on error
                    return stateText
                end try
            end tell
            """
            guard let compiled = NSAppleScript(source: source) else { return nil }
            var compileError: NSDictionary?
            guard compiled.compileAndReturnError(&compileError) else { return nil }
            cache[player.scriptName] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue else { return nil }
        return parse(text, bundleIdentifier: player.bundleIdentifier)
    }

    /// Parses the script output. Visible for verification.
    static func parse(_ text: String, bundleIdentifier: String) -> Snapshot {
        let lines = text.components(separatedBy: "\n")
        let playing = lines.first == "PLAYING"
        guard lines.count >= 4 else {
            return Snapshot(isPlaying: playing, title: "", artist: "", album: "", bundleIdentifier: bundleIdentifier, artworkURL: nil)
        }
        let artworkURL = lines.count >= 5 ? URL(string: lines[4]) : nil
        return Snapshot(
            isPlaying: playing,
            title: lines[1],
            artist: lines[2],
            album: lines[3],
            bundleIdentifier: bundleIdentifier,
            artworkURL: artworkURL
        )
    }
}
