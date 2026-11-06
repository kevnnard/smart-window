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
    public let isActive: Bool

    public init(id: String, name: String, category: String, icon: NSImage?, isActive: Bool) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.isActive = isActive
    }
}

// MARK: - NowPlayingService

/// Monitors the current track in Spotify or Apple Music, or active audio streams from browsers,
/// terminals (Ghostty), and other media applications via CoreAudio.
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
        guard let id = playerBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Actions

    /// Brings the running player to the front. Does nothing when no player is running.
    func openPlayer() {
        guard let id = playerBundleIdentifier else { return }
        openSource(id)
    }

    /// Brings the specified application or audio source to the front.
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

    func perform(_ action: TransportAction) {
        lastCommandError = nil
        do {
            try Self.send(action, bundleIdentifier: playerBundleIdentifier,
                          runningIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                          execute: { source in
                guard let script = NSAppleScript(source: source) else { throw TransportError.failed }
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let error { throw NSError(domain: "SmartWindow.Player", code: 1, userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Player command failed. Check Automation permission."]) }
            }, refresh: poll)
        } catch {
            lastCommandError = error.localizedDescription
        }
    }

    enum TransportError: LocalizedError {
        case unavailable, failed
        var errorDescription: String? {
            switch self {
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
        apply(Self.readSnapshot(using: &compiledScripts))
    }

    private func apply(_ snapshot: Snapshot) {
        if snapshot.isPlaying != isPlaying { isPlaying = snapshot.isPlaying }
        if snapshot.title != trackTitle { trackTitle = snapshot.title }
        if snapshot.artist != artistName { artistName = snapshot.artist }
        if snapshot.album != albumName { albumName = snapshot.album }
        if snapshot.bundleIdentifier != playerBundleIdentifier {
            playerBundleIdentifier = snapshot.bundleIdentifier
        }
        let activeID = snapshot.bundleIdentifier ?? "com.spotify.client"
        sourceDisplayName = Self.displayNameForBundleID(activeID)
        sourceCategory = Self.categoryForBundleID(activeID)
        detectedSources = Self.collectRunningSources(activeBundleID: snapshot.bundleIdentifier)

        if snapshot.artworkURL != artworkURL {
            artworkURL = snapshot.artworkURL
            loadArtwork(from: snapshot.artworkURL)
        }
    }

    static func categoryForBundleID(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("spotify") { return "spotify" }
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("browser") || lower.contains("brave") { return "youtube" }
        if lower.contains("ghostty") || lower.contains("terminal") || lower.contains("iterm") { return "ghostty" }
        if lower.contains("music") || lower.contains("podcast") { return "music" }
        return "media"
    }

    static func displayNameForBundleID(_ id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("spotify") { return "Spotify" }
        if lower.contains("music") { return "Apple Music" }
        if lower.contains("ghostty") { return "Ghostty" }
        if lower.contains("iterm") { return "iTerm2" }
        if lower.contains("terminal") { return "Terminal" }
        if lower.contains("chrome") { return "Google Chrome" }
        if lower.contains("safari") { return "Safari" }
        if lower.contains("arc") { return "Arc" }
        if lower.contains("brave") { return "Brave" }
        if lower.contains("vlc") { return "VLC" }
        if lower.contains("iina") { return "IINA" }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let name = app.localizedName {
            return name
        }
        return "Audio Stream"
    }

    static func collectRunningSources(activeBundleID: String?) -> [AudioSourceInfo] {
        let knownAppIDs: [(id: String, defaultName: String, category: String)] = [
            ("com.spotify.client", "Spotify", "spotify"),
            ("com.apple.Music", "Apple Music", "music"),
            ("com.mitchellh.ghostty", "Ghostty", "ghostty"),
            ("com.google.Chrome", "Google Chrome", "youtube"),
            ("com.apple.Safari", "Safari", "youtube"),
            ("company.thebrowser.Browser", "Arc", "youtube"),
            ("org.videolan.vlc", "VLC", "media"),
            ("com.colliderli.iina", "IINA", "media"),
            ("com.apple.Terminal", "Terminal", "ghostty"),
            ("com.googlecode.iterm2", "iTerm2", "ghostty")
        ]
        let runningApps = NSWorkspace.shared.runningApplications
        var sources: [AudioSourceInfo] = []
        for item in knownAppIDs {
            if let running = runningApps.first(where: { $0.bundleIdentifier == item.id }) {
                let icon = running.bundleURL.flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
                sources.append(AudioSourceInfo(
                    id: item.id,
                    name: running.localizedName ?? item.defaultName,
                    category: item.category,
                    icon: icon,
                    isActive: item.id == activeBundleID
                ))
            }
        }
        return sources
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

    /// The first running player that is playing wins. Otherwise the first running
    /// player (paused) is reported so the badge stays while the app is open.
    /// Only running players are queried so AppleScript never launches them.
    static func readSnapshot(using cache: inout [String: NSAppleScript]) -> Snapshot {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: Snapshot?
        for player in players where running.contains(player.bundleIdentifier) {
            guard let snapshot = query(player, cache: &cache) else { continue }
            if snapshot.isPlaying { return snapshot }
            if paused == nil { paused = snapshot }
        }

        // If no dedicated music player is actively playing, inspect system CoreAudio
        let audioActive = isCoreAudioOutputActive()
        if audioActive {
            // Check if a terminal (Ghostty), browser (Chrome/Safari/Arc), or media player is active
            let candidateIDs = [
                "com.mitchellh.ghostty",
                "com.google.Chrome",
                "com.apple.Safari",
                "company.thebrowser.Browser",
                "com.brave.Browser",
                "org.videolan.vlc",
                "com.colliderli.iina",
                "com.googlecode.iterm2",
                "com.apple.Terminal"
            ]
            // Prefer the frontmost app if it's one of the audio apps, otherwise the first running candidate
            let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let targetID: String?
            if let f = frontmostID, candidateIDs.contains(f) {
                targetID = f
            } else {
                targetID = candidateIDs.first(where: { running.contains($0) })
            }

            if let target = targetID {
                let appName = displayNameForBundleID(target)
                let category = categoryForBundleID(target)
                let streamTitle = category == "ghostty" ? "Terminal Audio Stream" : (category == "youtube" ? "Web Audio Stream" : "Media Playback")
                return Snapshot(
                    isPlaying: true,
                    title: streamTitle,
                    artist: appName,
                    album: "CoreAudio Output",
                    bundleIdentifier: target,
                    artworkURL: nil
                )
            }
        }

        return paused ?? .idle
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
