import AppKit
import Combine
import Foundation
import CoreAudio

// MARK: - AudioSourceInfo

public struct AudioSourceInfo: Identifiable, Equatable {
    public let id: String // bundle identifier
    public let name: String
    public let category: String // "spotify", "youtube", "ghostty", "music", "media"
    public let icon: NSImage?
    /// The source is the main one shown in the pill and targeted by the controls.
    public let isActive: Bool
    /// A process of the source is outputting audio (on macOS 13, the player state for AppleScript players).
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

/// Monitors the current track in Spotify or Apple Music, and the apps producing sound
/// (browsers, terminals, any app) via per-process CoreAudio data.
@MainActor
final class NowPlayingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var trackTitle: String = ""
    @Published private(set) var artistName: String = ""
    @Published private(set) var albumName: String = ""
    /// Bundle identifier of the running player, if any (set even while paused).
    @Published private(set) var playerBundleIdentifier: String?
    /// Album artwork when the player exposes it (Spotify), else nil.
    @Published private(set) var artwork: NSImage?
    /// Human-friendly name of the current source app (e.g. "Spotify", "Ghostty", "Chrome").
    @Published private(set) var sourceDisplayName: String = "Spotify"
    /// Category for badge styling: "spotify", "youtube", "ghostty", "music", "media".
    @Published private(set) var sourceCategory: String = "spotify"
    /// Active media/audio sources detected on the system.
    @Published private(set) var detectedSources: [AudioSourceInfo] = []
    /// Source chosen by the user; cleared when it is no longer detected, or stops while another source plays.
    @Published private(set) var selectedSourceID: String?
    /// Whether the selected source has been seen playing since it was selected. A source picked
    /// while paused stays selected until it plays and then stops.
    private var selectionWasPlaying = false

    /// There is a main source the transport controls can target.
    var canControl: Bool {
        playerBundleIdentifier != nil
    }

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

    /// Brings the specified application or audio source to the front.
    func openSource(_ bundleIdentifier: String) {
        // Generic sources have no app to bring forward.
        guard !Self.isSyntheticSource(bundleIdentifier) else { return }
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
        /// Allowlisted AppleScript command to the player with this bundle id.
        case appleScript(String)
        /// System media keys; they reach the app macOS treats as now playing.
        case mediaKey
    }

    static func route(for bundleIdentifier: String?) -> TransportRoute? {
        guard let id = bundleIdentifier else { return nil }
        return players.contains(where: { $0.bundleIdentifier == id }) ? .appleScript(id) : .mediaKey
    }

    func perform(_ action: TransportAction) {
        if lastCommandError != nil { lastCommandError = nil }
        do {
            switch Self.route(for: playerBundleIdentifier) {
            case .none:
                throw TransportError.noSource
            case .mediaKey:
                try MediaKeyService.post(action)
                poll()
            case .appleScript(let id):
                try sendAppleScript(action, bundleIdentifier: id)
            }
        } catch {
            lastCommandError = error.localizedDescription
        }
    }

    private func sendAppleScript(_ action: TransportAction, bundleIdentifier: String) throws {
        try Self.send(action, bundleIdentifier: bundleIdentifier,
                      runningIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                      execute: { source in
            guard let script = NSAppleScript(source: source) else { throw TransportError.failed }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error { throw NSError(domain: "SmartWindow.Player", code: 1, userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Player command failed. Check Automation permission."]) }
        }, refresh: poll)
    }

    enum TransportError: LocalizedError {
        case unavailable, failed, noSource
        var errorDescription: String? {
            switch self {
            case .noSource: return "No audio source is available to control."
            case .unavailable: return "The supported player is no longer running."
            case .failed: return "Could not control the player. Check Automation permission."
            }
        }
    }

    static func send(_ action: TransportAction, bundleIdentifier: String?, runningIDs: Set<String>,
                     execute: (String) throws -> Void, refresh: () -> Void) throws {
        guard let id = bundleIdentifier, players.contains(where: { $0.bundleIdentifier == id }),
              runningIDs.contains(id) else { throw TransportError.unavailable }
        // The ID and command are allowlisted; no track text or external input enters the script.
        let source = """
        if application id "\(id)" is not running then error "Player is no longer running."
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

    struct Snapshot: Equatable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var bundleIdentifier: String?
        var artworkURL: URL?

        static let idle = Snapshot(isPlaying: false, title: "", artist: "", album: "", bundleIdentifier: nil, artworkURL: nil)
    }

    private var pollTimer: Timer?
    private var compiledScripts: [String: NSAppleScript] = [:]
    private let pollInterval: TimeInterval = 2.0
    private var artworkURL: URL?
    private var artworkTask: Task<Void, Never>?
    private var playerSnapshots: [Snapshot] = []
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
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        playerSnapshots = Self.readPlayerSnapshots(using: &compiledScripts)
        let resolved = AudioSourceDetector.currentSources()
        let deviceActive = resolved == nil && Self.isCoreAudioOutputActive()
        candidateSources = Self.mergeSources(players: playerSnapshots, resolved: resolved,
                                             deviceOutputActive: deviceActive, icon: icon(for:))
        recompute()
    }

    /// Picks the main source from the last poll and publishes only the values that changed.
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
                                     sources: candidateSources)
        let sources = candidateSources.map {
            AudioSourceInfo(id: $0.id, name: $0.name, category: $0.category, icon: $0.icon,
                            isActive: $0.id == mainID, isPlaying: $0.isPlaying)
        }
        if sources != detectedSources { detectedSources = sources }
        let main = sources.first(where: { $0.id == mainID })
        apply(Self.snapshot(for: main, players: playerSnapshots), main: main)
    }

    private func apply(_ snapshot: Snapshot, main: AudioSourceInfo?) {
        if snapshot.isPlaying != isPlaying { isPlaying = snapshot.isPlaying }
        if snapshot.title != trackTitle { trackTitle = snapshot.title }
        if snapshot.artist != artistName { artistName = snapshot.artist }
        if snapshot.album != albumName { albumName = snapshot.album }
        if snapshot.bundleIdentifier != playerBundleIdentifier {
            playerBundleIdentifier = snapshot.bundleIdentifier
        }
        let name = main?.name ?? "Spotify"
        let category = main?.category ?? "spotify"
        if name != sourceDisplayName { sourceDisplayName = name }
        if category != sourceCategory { sourceCategory = category }

        if snapshot.artworkURL != artworkURL {
            artworkURL = snapshot.artworkURL
            loadArtwork(from: snapshot.artworkURL)
        }
    }

    /// App icons are fetched once per bundle id, not on every poll.
    private func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
        else { return nil }
        iconCache[bundleID] = icon
        return icon
    }

    // MARK: - Sources

    /// Generic source for unattributed output, and the placeholder when only device-level output is known (macOS 13).
    static let systemAudioID = AudioSourceDetector.systemAudioID

    /// Generic sources that do not correspond to an app bundle.
    static func isSyntheticSource(_ id: String) -> Bool {
        id == AudioSourceDetector.systemAudioID || id == AudioSourceDetector.webAudioID
    }

    /// The selection holds while it is detected, unless it was playing, stopped, and another source
    /// now plays; then it is cleared so selection falls back to automatic. A source picked while
    /// paused (`selectionWasPlaying == false`) therefore stays the main source after the click.
    static func retainedSelection(_ selected: String?, selectionWasPlaying: Bool = true,
                                  sources: [AudioSourceInfo]) -> String? {
        guard let selected, let source = sources.first(where: { $0.id == selected }) else { return nil }
        if source.isPlaying || !selectionWasPlaying || !sources.contains(where: \.isPlaying) { return selected }
        return nil
    }

    /// Running AppleScript players (playing or paused) first, then other sources outputting audio.
    /// With per-process data a player plays only while one of its processes outputs audio; without it
    /// (macOS 13) the player state is used and a generic system source stands in for unattributed output.
    static func mergeSources(players snapshots: [Snapshot], resolved: [AudioSourceDetector.ResolvedSource]?,
                             deviceOutputActive: Bool, icon: (String) -> NSImage?) -> [AudioSourceInfo] {
        var sources: [AudioSourceInfo] = snapshots.compactMap { snapshot in
            guard let id = snapshot.bundleIdentifier else { return nil }
            let playing = resolved.map { $0.contains(where: { $0.bundleID == id && $0.isPlaying }) }
                ?? snapshot.isPlaying
            return AudioSourceInfo(id: id, name: displayNameForBundleID(id), category: categoryForBundleID(id),
                                   icon: icon(id), isActive: false, isPlaying: playing)
        }
        if let resolved {
            for source in resolved where source.isPlaying && !sources.contains(where: { $0.id == source.bundleID }) {
                sources.append(AudioSourceInfo(id: source.bundleID, name: source.name,
                                               category: categoryForBundleID(source.bundleID),
                                               icon: icon(source.bundleID), isActive: false, isPlaying: true))
            }
        } else if deviceOutputActive, !snapshots.contains(where: \.isPlaying) {
            sources.append(AudioSourceInfo(id: systemAudioID, name: "System Audio", category: "media",
                                           icon: nil, isActive: false, isPlaying: true))
        }
        return sources
    }

    /// Retained selection (see `retainedSelection`); otherwise playing AppleScript player, first
    /// playing source, paused AppleScript player, or nil (idle).
    static func mainSource(selected: String?, selectionWasPlaying: Bool = true,
                           sources: [AudioSourceInfo]) -> String? {
        if let selected = retainedSelection(selected, selectionWasPlaying: selectionWasPlaying,
                                            sources: sources) { return selected }
        func isPlayer(_ source: AudioSourceInfo) -> Bool {
            players.contains(where: { $0.bundleIdentifier == source.id })
        }
        return sources.first(where: { isPlayer($0) && $0.isPlaying })?.id
            ?? sources.first(where: \.isPlaying)?.id
            ?? sources.first(where: isPlayer)?.id
    }

    /// AppleScript players keep their metadata; other sources only report the app, never a track.
    /// The playing state always comes from the merged source so the badge and the main display agree.
    static func snapshot(for main: AudioSourceInfo?, players snapshots: [Snapshot]) -> Snapshot {
        guard let main else { return .idle }
        if var player = snapshots.first(where: { $0.bundleIdentifier == main.id }) {
            player.isPlaying = main.isPlaying
            return player
        }
        let title: String
        switch main.category {
        case "youtube": title = "Web Audio"
        case "ghostty": title = "Terminal Audio"
        default: title = "Playing audio"
        }
        return Snapshot(isPlaying: main.isPlaying, title: title, artist: main.name, album: "",
                        bundleIdentifier: main.id, artworkURL: nil)
    }

    static func categoryForBundleID(_ id: String) -> String {
        if id == AudioSourceDetector.webAudioID { return "youtube" }
        if id == AudioSourceDetector.systemAudioID { return "media" }
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
            return NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
                ?? "Audio Stream"
        }
    }

    /// Checks via macOS CoreAudio if the default output device is actively playing audio.
    static func isCoreAudioOutputActive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutputDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID) == noErr,
              defaultOutputDeviceID != 0 else {
            return false
        }
        var isRunningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(defaultOutputDeviceID, &isRunningAddress, 0, nil, &size, &isRunning) == noErr else {
            return false
        }
        return isRunning != 0
    }

    private func loadArtwork(from url: URL?) {
        artworkTask?.cancel()
        guard let url else {
            artwork = nil
            return
        }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return }
            self?.artwork = image
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
