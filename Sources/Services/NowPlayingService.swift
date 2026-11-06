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
    /// The source reports that it is playing (MediaRemote for the Now Playing app, AppleScript for players).
    public let isPlaying: Bool

    public init(id: String, name: String, category: String, icon: NSImage?, isActive: Bool, isPlaying: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.isActive = isActive
        self.isPlaying = isPlaying
    }

    /// Icons are excluded so polling does not republish when only the NSImage instance differs.
    public static func == (lhs: AudioSourceInfo, rhs: AudioSourceInfo) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.category == rhs.category
            && lhs.isActive == rhs.isActive && lhs.isPlaying == rhs.isPlaying
    }
}

// MARK: - NowPlayingService

/// Shows the media session macOS reports as Now Playing (MediaRemote through mediaremote-adapter)
/// plus running Spotify and Apple Music (AppleScript). Without the adapter only the AppleScript
/// players are shown.
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
    /// Media sources: the Now Playing app and running Spotify/Music.
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
        /// The main source is the Now Playing app: adapter `send`.
        case adapter
        /// Allowlisted AppleScript command to the player with this bundle id.
        case appleScript(String)
        /// No command can reach only this app.
        case unavailable(String)
    }

    static let notNowPlayingReason = "This app can only be controlled while it is the Mac's Now Playing app."

    /// The adapter reaches only the Now Playing app and AppleScript only Spotify/Music, so any
    /// other app gets no route rather than a command that could reach another app.
    static func route(for bundleIdentifier: String?, nowPlayingID: String?) -> TransportRoute? {
        guard let id = bundleIdentifier else { return nil }
        if id == nowPlayingID { return .adapter }
        if isPlayer(id) { return .appleScript(id) }
        return .unavailable(notNowPlayingReason)
    }

    func perform(_ action: TransportAction) {
        if lastCommandError != nil { lastCommandError = nil }
        switch Self.route(for: playerBundleIdentifier, nowPlayingID: nowPlayingID) {
        case .none:
            lastCommandError = TransportError.noSource.localizedDescription
        case .unavailable(let reason):
            lastCommandError = reason
        case .adapter:
            adapter.send(action) { [weak self] error in
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
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var compiledScripts: [String: NSAppleScript] = [:]
    private let pollInterval: TimeInterval = 2.0
    private var artworkSource: ArtworkSource = .none
    private var artworkTask: Task<Void, Never>?
    private var playerSnapshots: [Snapshot] = []
    /// The adapter's session; nil while nothing plays or the adapter is unavailable.
    private var nowPlayingInfo: NowPlayingInfo?
    private var candidateSources: [AudioSourceInfo] = []
    private var iconCache: [String: NSImage] = [:]

    /// The Now Playing app, when the adapter reports one.
    private var nowPlayingID: String? { nowPlayingInfo?.ownerBundleIdentifier }

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
        adapter.start()
        adapter.$info.combineLatest(adapter.$adapterAvailable)
            .sink { [weak self] info, available in
                self?.adapterChanged(available ? info : nil)
            }
            .store(in: &cancellables)
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func adapterChanged(_ info: NowPlayingInfo?) {
        guard info != nowPlayingInfo else { return }
        nowPlayingInfo = info
        rebuildSources()
    }

    private func poll() {
        playerSnapshots = Self.readPlayerSnapshots(using: &compiledScripts)
        rebuildSources()
    }

    private func rebuildSources() {
        candidateSources = Self.mergeSources(nowPlaying: nowPlayingInfo, players: playerSnapshots,
                                             name: Self.displayNameForBundleID, icon: icon(for:))
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
                                     sources: candidateSources, nowPlayingID: nowPlayingID)
        let sources = candidateSources.map {
            AudioSourceInfo(id: $0.id, name: $0.name, category: $0.category, icon: $0.icon,
                            isActive: $0.id == mainID, isPlaying: $0.isPlaying)
        }
        if sources != detectedSources { detectedSources = sources }
        let main = sources.first(where: { $0.id == mainID })
        apply(Self.snapshot(for: main, nowPlaying: nowPlayingInfo, players: playerSnapshots), main: main)
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

        let route = Self.route(for: snapshot.bundleIdentifier, nowPlayingID: nowPlayingID)
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

    /// The Now Playing app (parent app when set, else its bundle id) first, then running AppleScript
    /// players. A Now Playing Spotify or Music is one source with the adapter's playing state.
    /// Apps without a media session never appear.
    static func mergeSources(nowPlaying: NowPlayingInfo?, players snapshots: [Snapshot],
                             name: (String) -> String, icon: (String) -> NSImage?) -> [AudioSourceInfo] {
        var sources: [AudioSourceInfo] = []
        if let owner = nowPlaying?.ownerBundleIdentifier {
            sources.append(AudioSourceInfo(id: owner, name: name(owner), category: categoryForBundleID(owner),
                                           icon: icon(owner), isActive: false, isPlaying: nowPlaying?.playing ?? false))
        }
        for snapshot in snapshots {
            guard let id = snapshot.bundleIdentifier, !sources.contains(where: { $0.id == id }) else { continue }
            sources.append(AudioSourceInfo(id: id, name: name(id), category: categoryForBundleID(id),
                                           icon: icon(id), isActive: false, isPlaying: snapshot.isPlaying))
        }
        return sources
    }

    /// Retained selection (see `retainedSelection`); otherwise the Now Playing app, a playing
    /// AppleScript player, a paused AppleScript player, or nil (idle).
    static func mainSource(selected: String?, selectionWasPlaying: Bool = true,
                           sources: [AudioSourceInfo], nowPlayingID: String?) -> String? {
        if let selected = retainedSelection(selected, selectionWasPlaying: selectionWasPlaying,
                                            sources: sources) { return selected }
        if let nowPlayingID, sources.contains(where: { $0.id == nowPlayingID }) { return nowPlayingID }
        return sources.first(where: { isPlayer($0.id) && $0.isPlaying })?.id
            ?? sources.first(where: { isPlayer($0.id) })?.id
    }

    /// The Now Playing app shows the adapter's metadata, with the AppleScript player as backup for
    /// missing fields; AppleScript players otherwise keep their own metadata. The playing state
    /// always comes from the merged source so the badge and the main display agree.
    static func snapshot(for main: AudioSourceInfo?, nowPlaying: NowPlayingInfo?, players snapshots: [Snapshot]) -> Snapshot {
        guard let main else { return .idle }
        let player = snapshots.first(where: { $0.bundleIdentifier == main.id })
        if let info = nowPlaying, info.ownerBundleIdentifier == main.id {
            func text(_ value: String, _ backup: String?) -> String { value.isEmpty ? backup ?? "" : value }
            return Snapshot(isPlaying: main.isPlaying,
                            title: text(info.title, player?.title),
                            artist: text(info.artist, player?.artist),
                            album: text(info.album, player?.album),
                            bundleIdentifier: main.id,
                            artworkURL: info.artworkData == nil ? player?.artworkURL : nil,
                            artworkData: info.artworkData,
                            duration: info.duration,
                            elapsedTime: info.elapsedTime,
                            elapsedTimestamp: info.timestamp,
                            playbackRate: main.isPlaying ? info.playbackRate ?? 1 : 0)
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
