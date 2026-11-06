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
        try check(orphan == [.init(bundleID: "system-audio", name: "System Audio", isPlaying: true)], "unattributable outputting process is generic System Audio")

        let webkit = resolve([.init(pid: 700, bundleID: "com.apple.WebKit.GPU", isOutputting: true),
                              .init(pid: 701, bundleID: "com.apple.WebKit.WebContent", isOutputting: true)])
        try check(webkit == [.init(bundleID: "webkit-audio", name: "Web content", isPlaying: true)], "unattributable WebKit output is one Web content source")
        try check(!webkit.contains(where: { $0.bundleID == "com.apple.Safari" }), "WebKit audio is not attributed to Safari")

        let silentOrphans = resolve([.init(pid: 600, bundleID: "com.apple.some.daemon", isOutputting: false),
                                     .init(pid: 700, bundleID: "com.apple.WebKit.GPU", isOutputting: false)])
        try check(silentOrphans.isEmpty, "unattributable silent process is dropped")

        let noBundleOrphan = resolve([.init(pid: 600, bundleID: nil, isOutputting: true)])
        try check(noBundleOrphan.map(\.bundleID) == ["system-audio"], "unattributable process without bundle id is System Audio")

        // Merge: generic sources
        let mergedWeb = NowPlayingService.mergeSources(players: [], resolved: webkit, deviceOutputActive: false, icon: { _ in nil })
        try check(mergedWeb.count == 1 && mergedWeb[0].id == "webkit-audio" && mergedWeb[0].name == "Web content"
                  && mergedWeb[0].category == "youtube" && mergedWeb[0].isPlaying, "Web content merges as a playing browser-styled source")
        try check(NowPlayingService.route(for: "webkit-audio") == .mediaKey, "Web content uses media keys")
        let mergedSystem = NowPlayingService.mergeSources(players: [], resolved: orphan, deviceOutputActive: false, icon: { _ in nil })
        try check(mergedSystem.map(\.id) == ["system-audio"] && mergedSystem[0].category == "media" && mergedSystem[0].isPlaying, "System Audio merges as a playing media source")
        try check(NowPlayingService.route(for: "system-audio") == .mediaKey, "System Audio uses media keys")
        try check(NowPlayingService.isSyntheticSource("webkit-audio") && NowPlayingService.isSyntheticSource("system-audio")
                  && !NowPlayingService.isSyntheticSource("com.google.Chrome"), "synthetic ids are not openable apps")

        // Merge: playing state of AppleScript players
        let spotifySnapshot = { (playing: Bool) in
            NowPlayingService.Snapshot(isPlaying: playing, title: "Song", artist: "Band", album: "LP",
                                       bundleIdentifier: "com.spotify.client", artworkURL: URL(string: "https://example.com/a.jpg"))
        }
        let spotifyOutput = AudioSourceDetector.ResolvedSource(bundleID: "com.spotify.client", name: "Spotify", isPlaying: true)
        let claimsPlaying = NowPlayingService.mergeSources(players: [spotifySnapshot(true)], resolved: [], deviceOutputActive: false, icon: { _ in nil })
        try check(claimsPlaying.map(\.isPlaying) == [false], "AppleScript playing without output is not playing (per-process mode)")
        try check(NowPlayingService.snapshot(for: claimsPlaying.first, players: [spotifySnapshot(true)]).isPlaying == false, "main snapshot agrees: not playing")
        let pausedOutputting = NowPlayingService.mergeSources(players: [spotifySnapshot(false)], resolved: [spotifyOutput], deviceOutputActive: false, icon: { _ in nil })
        try check(pausedOutputting.map(\.isPlaying) == [true], "AppleScript paused but outputting is playing")
        let pausedMain = NowPlayingService.snapshot(for: pausedOutputting.first, players: [spotifySnapshot(false)])
        try check(pausedMain.isPlaying && pausedMain.title == "Song" && pausedMain.artist == "Band" && pausedMain.album == "LP"
                  && pausedMain.artworkURL != nil, "main snapshot is playing and keeps AppleScript metadata")
        let legacy = NowPlayingService.mergeSources(players: [spotifySnapshot(true)], resolved: nil, deviceOutputActive: true, icon: { _ in nil })
        try check(legacy.map(\.isPlaying) == [true], "macOS 13 keeps the AppleScript playing state")
        let legacyPaused = NowPlayingService.mergeSources(players: [spotifySnapshot(false)], resolved: nil, deviceOutputActive: false, icon: { _ in nil })
        try check(legacyPaused.map(\.isPlaying) == [false], "macOS 13 keeps the AppleScript paused state")

        // Selection
        func source(_ id: String, playing: Bool) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: false, isPlaying: playing)
        }
        let spotifyPaused = source("com.spotify.client", playing: false)
        let musicPlaying = source("com.apple.Music", playing: true)
        let chromePlaying = source("com.google.Chrome", playing: true)
        let ghosttyPlaying = source("com.mitchellh.ghostty", playing: true)

        try check(NowPlayingService.mainSource(selected: "com.mitchellh.ghostty", sources: [chromePlaying, ghosttyPlaying]) == "com.mitchellh.ghostty", "selected source wins")
        try check(NowPlayingService.mainSource(selected: "com.spotify.client", sources: [source("com.google.Chrome", playing: false), spotifyPaused]) == "com.spotify.client", "selected paused player wins when nothing else plays")
        try check(NowPlayingService.retainedSelection("com.spotify.client", sources: [spotifyPaused]) == "com.spotify.client", "selected paused player stays selected when nothing else plays")
        try check(NowPlayingService.mainSource(selected: "com.spotify.client", sources: [chromePlaying, spotifyPaused]) == "com.google.Chrome", "selected paused player loses when another source plays")
        try check(NowPlayingService.retainedSelection("com.spotify.client", sources: [chromePlaying, spotifyPaused]) == nil, "selection cleared when it stops and another source plays")
        try check(NowPlayingService.retainedSelection("com.mitchellh.ghostty", sources: [chromePlaying, ghosttyPlaying]) == "com.mitchellh.ghostty", "playing selection holds")
        try check(NowPlayingService.retainedSelection("com.spotify.client", selectionWasPlaying: false, sources: [chromePlaying, spotifyPaused]) == "com.spotify.client", "paused source picked by a click stays selected while another plays")
        try check(NowPlayingService.mainSource(selected: "com.spotify.client", selectionWasPlaying: false, sources: [chromePlaying, spotifyPaused]) == "com.spotify.client", "paused source picked by a click is the main source")
        try check(NowPlayingService.retainedSelection("com.gone.app", selectionWasPlaying: false, sources: [chromePlaying]) == nil, "clicked source that disappears is cleared")
        try check(NowPlayingService.retainedSelection("com.gone.app", sources: [chromePlaying]) == nil, "stale selection cleared")
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
