import AppKit

@main
struct AudioSourcesProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: Audio source attribution, selection and transport routing") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }

        // Process tree: 100 Chrome, 101 Chrome helper, 200 Ghostty <- 201 zsh <- 202 mpv,
        // 300/301 Electron app helpers, 400 SmartWindow, 500 unknown app, 600 orphan daemon.
        let apps: [pid_t: (bundleID: String, name: String)] = [
            100: ("com.google.Chrome", "Google Chrome"),
            200: ("com.mitchellh.ghostty", "Ghostty"),
            300: ("com.example.Notes", "Notes Deluxe"),
            400: ("com.smartwindow.app", "SmartWindow"),
            500: ("org.example.Radio", "Radio Kit"),
        ]
        let parents: [pid_t: pid_t] = [101: 1, 201: 200, 202: 201, 301: 300, 302: 300, 401: 400, 600: 1]
        func resolve(_ processes: [AudioSourceDetector.AudioProcess]) -> [AudioSourceDetector.ResolvedSource] {
            AudioSourceDetector.resolveSources(
                audioProcesses: processes,
                appForPID: { apps[$0] },
                appForBundleID: { id in apps.values.first(where: { $0.bundleID == id })?.name },
                parentPID: { parents[$0] },
                ownBundleID: "com.smartwindow.app")
        }

        try check(AudioSourceDetector.ownerBundleID(for: "com.google.Chrome.helper") == "com.google.Chrome", "helper suffix stripped")
        try check(AudioSourceDetector.ownerBundleID(for: "com.google.Chrome") == "com.google.Chrome", "app bundle id kept")
        let chrome = resolve([.init(pid: 101, bundleID: "com.google.Chrome.helper", isOutputting: true)])
        try check(chrome == [.init(bundleID: "com.google.Chrome", name: "Google Chrome", isPlaying: true)], "helper maps to parent app")

        let mpv = resolve([.init(pid: 202, bundleID: nil, isOutputting: true)])
        try check(mpv == [.init(bundleID: "com.mitchellh.ghostty", name: "Ghostty", isPlaying: true)], "CLI child maps through parent chain")

        let electron = resolve([.init(pid: 301, bundleID: "com.github.Electron.helper", isOutputting: true)])
        try check(electron.map(\.bundleID) == ["com.example.Notes"], "Electron helper maps to owning app, not Electron")

        let idle = resolve([.init(pid: 101, bundleID: "com.google.Chrome.helper", isOutputting: false)])
        try check(idle.allSatisfy { !$0.isPlaying }, "non-outputting process is not playing")

        let own = resolve([.init(pid: 400, bundleID: "com.smartwindow.app", isOutputting: true),
                           .init(pid: 401, bundleID: nil, isOutputting: true)])
        try check(own.isEmpty, "SmartWindow excluded")

        let dedup = resolve([.init(pid: 301, bundleID: "com.github.Electron.helper", isOutputting: false),
                             .init(pid: 302, bundleID: "com.github.Electron.helper", isOutputting: true)])
        try check(dedup == [.init(bundleID: "com.example.Notes", name: "Notes Deluxe", isPlaying: true)], "processes of one app deduplicate")

        let unknown = resolve([.init(pid: 500, bundleID: "org.example.Radio", isOutputting: true)])
        try check(unknown.first?.name == "Radio Kit", "unknown app keeps its real name")

        let orphan = resolve([.init(pid: 600, bundleID: "com.apple.some.daemon", isOutputting: true)])
        try check(orphan.isEmpty, "unattributable process is not invented as a source")

        // Selection
        func source(_ id: String, playing: Bool) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: false, isPlaying: playing)
        }
        let spotifyPaused = source("com.spotify.client", playing: false)
        let musicPlaying = source("com.apple.Music", playing: true)
        let chromePlaying = source("com.google.Chrome", playing: true)
        let ghosttyPlaying = source("com.mitchellh.ghostty", playing: true)

        try check(NowPlayingService.mainSource(selected: "com.mitchellh.ghostty", sources: [chromePlaying, ghosttyPlaying]) == "com.mitchellh.ghostty", "selected source wins")
        try check(NowPlayingService.mainSource(selected: "com.spotify.client", sources: [chromePlaying, spotifyPaused]) == "com.spotify.client", "selected paused player wins")
        try check(NowPlayingService.mainSource(selected: "com.gone.app", sources: [chromePlaying, ghosttyPlaying]) == "com.google.Chrome", "stale selection falls back to auto")
        try check(NowPlayingService.mainSource(selected: nil, sources: [chromePlaying, musicPlaying]) == "com.apple.Music", "playing AppleScript player first")
        try check(NowPlayingService.mainSource(selected: nil, sources: [spotifyPaused, ghosttyPlaying]) == "com.mitchellh.ghostty", "outputting source before paused player")
        try check(NowPlayingService.mainSource(selected: nil, sources: [source("com.google.Chrome", playing: false), spotifyPaused]) == "com.spotify.client", "paused player before idle")
        try check(NowPlayingService.mainSource(selected: nil, sources: [source("com.google.Chrome", playing: false)]) == nil, "idle when nothing plays")
        try check(NowPlayingService.mainSource(selected: nil, sources: []) == nil, "idle with no sources")

        // Routing
        try check(NowPlayingService.route(for: "com.spotify.client") == .appleScript("com.spotify.client"), "Spotify uses AppleScript")
        try check(NowPlayingService.route(for: "com.apple.Music") == .appleScript("com.apple.Music"), "Music uses AppleScript")
        for id in ["com.google.Chrome", "com.mitchellh.ghostty", "org.example.Radio"] {
            try check(NowPlayingService.route(for: id) == .mediaKey, "\(id) uses media keys")
        }
        try check(NowPlayingService.route(for: nil) == nil, "no source has no route")
        try check(MediaKeyService.keyCode(for: .playPause) == 16 && MediaKeyService.keyCode(for: .next) == 17
                  && MediaKeyService.keyCode(for: .previous) == 18, "media key codes")

        // Equality ignores image identity
        try check(source("a", playing: true) == AudioSourceInfo(id: "a", name: "a", category: "media", icon: NSImage(), isActive: false, isPlaying: true), "equality ignores icon")
        try check(source("a", playing: true) != source("a", playing: false), "equality tracks playing state")
    }
}
