import AppKit

@main
struct AudioSourcesProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: media session sources, selection, transport routing, fallback and error mapping") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        typealias Service = NowPlayingService
        let dia = "company.thebrowser.dia", music = "com.apple.Music", spotifyID = "com.spotify.client"
        let names = ["com.google.Chrome": "Google Chrome", spotifyID: "Spotify", music: "Apple Music", dia: "Dia"]
        func name(_ id: String) -> String { names[id] ?? id }
        func merge(_ sessions: [MediaSession], _ players: [Service.Snapshot]) -> [AudioSourceInfo] {
            Service.mergeSources(sessions: sessions, players: players, name: name, icon: { _ in nil })
        }
        func spotify(playing: Bool) -> Service.Snapshot {
            Service.Snapshot(isPlaying: playing, title: "Script Song", artist: "Script Band", album: "Script LP",
                             bundleIdentifier: spotifyID, artworkURL: URL(string: "https://example.com/a.jpg"))
        }
        let musicScript = Service.Snapshot(isPlaying: false, title: "Tune", artist: "Singer", album: "Record",
                                           bundleIdentifier: music, artworkURL: nil)
        let artwork = Data([1, 2, 3])
        let diaSession = MediaSession(bundleIdentifier: dia, displayName: "Dia", title: "YouTube video", artist: "Channel",
                                      duration: 300, elapsedTime: 12, timestamp: Date(timeIntervalSince1970: 100),
                                      playbackRate: 1, playing: true, artworkData: artwork)
        let musicSession = MediaSession(bundleIdentifier: music, title: "Am Healing", artist: "Fecent Ricco", album: "EP",
                                        duration: 154, elapsedTime: 38, playbackRate: 0, playing: false)
        let spotifySession = MediaSession(bundleIdentifier: spotifyID, title: "Session Song", artist: "Session Band",
                                          album: "Session LP", duration: 200, elapsedTime: 50,
                                          timestamp: Date(timeIntervalSince1970: 200), playbackRate: 1, playing: false,
                                          artworkData: artwork)

        // Sources: one per session (Dia playing and current, Music and Spotify paused)
        let three = merge([diaSession, musicSession, spotifySession], [spotify(playing: false), musicScript])
        try check(three.map(\.id) == [dia, music, spotifyID], "3 sessions are 3 sources, no duplicates")
        try check(three.map(\.isPlaying) == [true, false, false], "session playing states")
        try check(three.allSatisfy(\.hasSession), "all three come from sessions")
        try check(three[0].name == "Dia" && three[0].category == "youtube", "Dia named and categorized as a browser")
        try check(Service.mainSource(selected: nil, sources: three, current: dia) == dia, "Dia playing and current is main")

        // Spotify with a session and running in AppleScript is one source with session metadata first
        let dedup = merge([spotifySession], [spotify(playing: true), musicScript])
        try check(dedup.map(\.id) == [spotifyID, music], "Spotify session plus running Spotify is one source")
        try check(dedup[0].hasSession && !dedup[1].hasSession, "Music without a session comes from AppleScript")
        try check(!dedup[0].isPlaying, "session playing state preferred over AppleScript")
        let dedupMain = Service.snapshot(for: dedup[0], sessions: [spotifySession], players: [spotify(playing: true)])
        try check(dedupMain.title == "Session Song" && dedupMain.artist == "Session Band" && dedupMain.album == "Session LP",
                  "session metadata preferred")
        try check(dedupMain.duration == 200 && dedupMain.elapsedTime == 50
                  && dedupMain.elapsedTimestamp == Date(timeIntervalSince1970: 200) && dedupMain.playbackRate == 0,
                  "session timing published, paused rate 0")
        try check(dedupMain.artworkData == artwork && dedupMain.artworkURL == nil, "session artwork preferred")
        let sparse = MediaSession(bundleIdentifier: spotifyID)
        let sparseSources = merge([sparse], [spotify(playing: true)])
        try check(sparseSources[0].isPlaying, "AppleScript backs up an unknown session playing state")
        let sparseMain = Service.snapshot(for: sparseSources[0], sessions: [sparse], players: [spotify(playing: true)])
        try check(sparseMain.title == "Script Song" && sparseMain.artist == "Script Band"
                  && sparseMain.artworkURL != nil && sparseMain.artworkData == nil && sparseMain.playbackRate == 1,
                  "AppleScript backs up missing session metadata")
        let diaMain = Service.snapshot(for: three[0], sessions: [diaSession, musicSession], players: [])
        try check(diaMain.bundleIdentifier == dia && diaMain.title == "YouTube video" && diaMain.duration == 300
                  && diaMain.elapsedTime == 12 && diaMain.playbackRate == 1 && diaMain.isPlaying, "Dia metadata and timing")

        // Owner resolution and duplicate sessions of one app
        let helperSession = MediaSession(bundleIdentifier: "com.google.Chrome.helper",
                                         parentApplicationBundleIdentifier: "com.google.Chrome", title: "Tab", playing: false)
        let helperPlaying = MediaSession(bundleIdentifier: "com.google.Chrome.helper2",
                                         parentApplicationBundleIdentifier: "com.google.Chrome", title: "Other tab", playing: true)
        let chrome = merge([helperSession, helperPlaying], [])
        try check(chrome.map(\.id) == ["com.google.Chrome"] && chrome[0].name == "Google Chrome" && chrome[0].isPlaying,
                  "sessions of one app are one source, the playing one wins")
        try check(Service.snapshot(for: chrome[0], sessions: [helperSession, helperPlaying], players: []).title == "Other tab",
                  "the playing session of the app is shown")

        // Running players without a session still appear; nothing else is invented
        let fallback = merge([], [spotify(playing: true), musicScript])
        try check(fallback.map(\.id) == [spotifyID, music], "running Spotify and Music without session from AppleScript")
        let fallbackMain = Service.snapshot(for: fallback[0], sessions: [], players: [spotify(playing: true), musicScript])
        try check(fallbackMain.title == "Script Song" && fallbackMain.duration == nil && fallbackMain.elapsedTime == nil
                  && fallbackMain.artworkData == nil && fallbackMain.isPlaying, "AppleScript metadata only")
        try check(merge([], []).isEmpty, "nothing running: no sources")
        try check(Service.snapshot(for: nil, sessions: [], players: []) == .idle, "no main source is idle")
        try check(!three.contains(where: { $0.id.lowercased().contains("moonlight") }), "app without media session absent")

        // Helper unavailable: the adapter's single session, as before; both unavailable: AppleScript only
        let chromeInfo = NowPlayingInfo(bundleIdentifier: "com.google.Chrome.helper",
                                        parentApplicationBundleIdentifier: "com.google.Chrome",
                                        title: "Video", playing: true)
        let viaAdapter = Service.effectiveSessions(helperAvailable: false, helperSessions: [diaSession],
                                                   helperCurrent: dia, adapterInfo: chromeInfo)
        try check(viaAdapter.sessions.map(\.ownerBundleIdentifier) == ["com.google.Chrome"]
                  && viaAdapter.current == "com.google.Chrome", "helper unavailable: the adapter's single session is current")
        let viaHelper = Service.effectiveSessions(helperAvailable: true, helperSessions: [diaSession, musicSession],
                                                  helperCurrent: music, adapterInfo: chromeInfo)
        try check(viaHelper.sessions.count == 2 && viaHelper.current == music, "helper available: its sessions and current")
        let none = Service.effectiveSessions(helperAvailable: false, helperSessions: [], helperCurrent: nil, adapterInfo: nil)
        try check(none.sessions.isEmpty && none.current == nil, "both unavailable: no sessions")
        let adapterSources = merge(viaAdapter.sessions, [spotify(playing: true)])
        try check(adapterSources.map(\.id) == ["com.google.Chrome", spotifyID], "adapter session first, then Spotify")
        try check(Service.mainSource(selected: nil, sources: adapterSources, current: viaAdapter.current) == "com.google.Chrome",
                  "adapter fallback: Now Playing app main")
        let pausedInfo = NowPlayingInfo(bundleIdentifier: music, title: "Tune", playing: false)
        let pausedAdapter = Service.effectiveSessions(helperAvailable: false, helperSessions: [], helperCurrent: nil,
                                                      adapterInfo: pausedInfo)
        let pausedSources = merge(pausedAdapter.sessions, [spotify(playing: true)])
        try check(Service.mainSource(selected: nil, sources: pausedSources, current: pausedAdapter.current) == music,
                  "adapter fallback: paused Now Playing app stays first, as before")
        try check(Service.runsAdapterStream(helperStatus: .unavailable), "adapter stream runs while the helper is unavailable")
        try check(!Service.runsAdapterStream(helperStatus: .available), "adapter stream stopped while the helper is healthy")
        try check(!Service.runsAdapterStream(helperStatus: .starting), "adapter stream not started while the helper starts")

        // Selection
        func source(_ id: String, playing: Bool, session: Bool = true) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: false, isPlaying: playing, hasSession: session)
        }
        let chromePlaying = source("com.google.Chrome", playing: true)
        let chromePaused = source("com.google.Chrome", playing: false)
        let spotifyPaused = source(spotifyID, playing: false, session: false)
        let spotifyPlaying = source(spotifyID, playing: true, session: false)
        let musicPaused = source(music, playing: false, session: false)
        let musicPlaying = source(music, playing: true, session: false)
        let diaPlaying = source(dia, playing: true)
        let musicSessionPlaying = source(music, playing: true)
        let musicSessionPaused = source(music, playing: false)
        let np = "com.google.Chrome"

        try check(Service.mainSource(selected: nil, sources: [musicSessionPlaying, diaPlaying], current: dia) == dia,
                  "auto: the current one among playing sessions")
        try check(Service.mainSource(selected: nil, sources: [musicSessionPaused, diaPlaying], current: music) == dia,
                  "auto: a playing session before a paused current one")
        try check(Service.mainSource(selected: nil, sources: [chromePaused, spotifyPlaying], current: np) == np,
                  "auto: current Now Playing app before an AppleScript player")
        try check(Service.mainSource(selected: nil, sources: [spotifyPaused, musicPlaying], current: nil) == music,
                  "auto: playing AppleScript player next")
        try check(Service.mainSource(selected: nil, sources: [spotifyPaused, musicPaused], current: nil) == spotifyID,
                  "auto: paused source last")
        try check(Service.mainSource(selected: nil, sources: [], current: nil) == nil, "auto: idle with no sources")
        try check(Service.mainSource(selected: spotifyID, selectionWasPlaying: false,
                                     sources: [chromePlaying, spotifyPaused], current: np) == spotifyID,
                  "clicked paused source stays main while another plays")
        try check(Service.retainedSelection(spotifyID, selectionWasPlaying: true,
                                            sources: [chromePlaying, spotifyPaused]) == nil,
                  "selection that played and stopped while another plays is cleared")
        try check(Service.mainSource(selected: spotifyID, selectionWasPlaying: true,
                                     sources: [chromePlaying, spotifyPaused], current: np) == np,
                  "cleared selection falls back to automatic")
        try check(Service.retainedSelection(spotifyID, selectionWasPlaying: true,
                                            sources: [chromePaused, spotifyPaused]) == spotifyID,
                  "stopped selection holds when nothing else plays")
        try check(Service.retainedSelection(spotifyID, sources: [chromePlaying, spotifyPlaying]) == spotifyID, "playing selection holds")
        try check(Service.retainedSelection("com.gone.app", selectionWasPlaying: false, sources: [chromePlaying]) == nil, "vanished selection cleared")

        // Routing: AppleScript for Spotify/Music, adapter only for the current Now Playing app, else nothing
        try check(Service.route(for: dia, current: dia, appName: "Dia") == .adapter(expectedOwner: dia),
                  "Dia main and current uses the adapter, bound to Dia")
        try check(Service.route(for: np, current: np, appName: "Google Chrome") == .adapter(expectedOwner: np),
                  "expected owner is the owning app")
        try check(Service.route(for: music, current: dia, appName: "Apple Music") == .appleScript(music),
                  "Music main, not current, uses AppleScript")
        try check(Service.route(for: spotifyID, current: spotifyID, appName: "Spotify") == .appleScript(spotifyID),
                  "Spotify always uses its targeted AppleScript")
        try check(Service.route(for: music, current: nil, appName: "Apple Music") == .appleScript(music),
                  "Music without any Now Playing reader uses AppleScript")
        let diaReason = "macOS only lets SmartWindow control Dia while it is the Mac's current Now Playing app."
        try check(Service.route(for: dia, current: music, appName: "Dia") == .unavailable(diaReason),
                  "Dia main while Music is current: no command, exact reason")
        try check(Service.unavailableReason(appName: "Dia") == diaReason, "reason names the app")
        try check(Service.route(for: dia, current: nil, appName: "Dia") == .unavailable(diaReason),
                  "no current Now Playing app: no command")
        try check(Service.route(for: nil, current: dia, appName: "") == nil, "no main source has no route")

        // Error mapping
        try check(Service.appleScriptErrorMessage(number: -1743, message: "Not authorized", appName: "Spotify")
                  == "SmartWindow is not allowed to control Spotify. Allow it in System Settings > Privacy & Security > Automation.",
                  "-1743 names the Automation setting")
        try check(Service.appleScriptErrorMessage(number: -600, message: "Application isn't running.", appName: "Music")
                  == "Music is not running.", "-600 names the app")
        try check(Service.appleScriptErrorMessage(number: -1728, message: "Can't get current track.", appName: "Music")
                  == "Music: Can't get current track. (error -1728)", "other errors keep message and number")
        try check(Service.appleScriptErrorMessage(number: nil, message: nil, appName: "Spotify")
                  == "Could not control Spotify.", "unknown error names the app")

        // Equality ignores image identity
        try check(source("a", playing: true) == AudioSourceInfo(id: "a", name: "a", category: "media", icon: NSImage(),
                                                                isActive: false, isPlaying: true, hasSession: true),
                  "equality ignores icon")
        try check(source("a", playing: true) != source("a", playing: false), "equality tracks playing state")
    }
}
