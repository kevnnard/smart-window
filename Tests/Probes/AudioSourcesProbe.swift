import AppKit

@main
struct AudioSourcesProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: Now Playing sources, selection, transport routing and error mapping") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        typealias Service = NowPlayingService
        let names = ["com.google.Chrome": "Google Chrome", "com.spotify.client": "Spotify", "com.apple.Music": "Apple Music"]
        func merge(_ nowPlaying: NowPlayingInfo?, _ players: [Service.Snapshot]) -> [AudioSourceInfo] {
            Service.mergeSources(nowPlaying: nowPlaying, players: players,
                                 name: { names[$0] ?? $0 }, icon: { _ in nil })
        }
        func spotify(playing: Bool) -> Service.Snapshot {
            Service.Snapshot(isPlaying: playing, title: "Script Song", artist: "Script Band", album: "Script LP",
                             bundleIdentifier: "com.spotify.client", artworkURL: URL(string: "https://example.com/a.jpg"))
        }
        let music = Service.Snapshot(isPlaying: false, title: "Tune", artist: "Singer", album: "Record",
                                     bundleIdentifier: "com.apple.Music", artworkURL: nil)
        let artwork = Data([1, 2, 3])
        let chromeSession = NowPlayingInfo(bundleIdentifier: "com.google.Chrome.helper",
                                           parentApplicationBundleIdentifier: "com.google.Chrome",
                                           title: "Video", artist: "Channel", duration: 300, elapsedTime: 12,
                                           timestamp: Date(timeIntervalSince1970: 100), playbackRate: 1, playing: true,
                                           artworkData: artwork, artworkMimeType: "image/png")

        // Sources: Now Playing app plus running AppleScript players, Now Playing first
        let two = merge(chromeSession, [spotify(playing: false)])
        try check(two.map(\.id) == ["com.google.Chrome", "com.spotify.client"], "Now Playing app first, then Spotify")
        try check(two[0].name == "Google Chrome" && two[0].category == "youtube" && two[0].isPlaying, "Now Playing app resolved through its parent")
        try check(!two[1].isPlaying, "Spotify keeps its AppleScript state")
        let ownBundle = merge(NowPlayingInfo(bundleIdentifier: "com.apple.Music", title: "Tune", playing: false), [])
        try check(ownBundle.map(\.id) == ["com.apple.Music"] && !ownBundle[0].isPlaying, "bundle id used when no parent is set")

        // Deduplication: Spotify is the Now Playing app
        let spotifySession = NowPlayingInfo(bundleIdentifier: "com.spotify.client", title: "Adapter Song",
                                            artist: "Adapter Band", album: "Adapter LP", duration: 200, elapsedTime: 50,
                                            timestamp: Date(timeIntervalSince1970: 200), playbackRate: 1, playing: true,
                                            artworkData: artwork, artworkMimeType: "image/jpeg")
        let dedup = merge(spotifySession, [spotify(playing: false), music])
        try check(dedup.map(\.id) == ["com.spotify.client", "com.apple.Music"], "Now Playing Spotify is one source")
        try check(dedup[0].isPlaying, "adapter playing state preferred")
        let dedupMain = Service.snapshot(for: dedup[0], nowPlaying: spotifySession, players: [spotify(playing: false), music])
        try check(dedupMain.title == "Adapter Song" && dedupMain.artist == "Adapter Band" && dedupMain.album == "Adapter LP",
                  "adapter metadata preferred")
        try check(dedupMain.duration == 200 && dedupMain.elapsedTime == 50
                  && dedupMain.elapsedTimestamp == Date(timeIntervalSince1970: 200) && dedupMain.playbackRate == 1,
                  "adapter timing published")
        try check(dedupMain.artworkData == artwork && dedupMain.isPlaying, "adapter artwork preferred")
        let sparse = NowPlayingInfo(bundleIdentifier: "com.spotify.client", playing: true)
        let sparseMain = Service.snapshot(for: merge(sparse, [spotify(playing: true)])[0], nowPlaying: sparse,
                                          players: [spotify(playing: true)])
        try check(sparseMain.title == "Script Song" && sparseMain.artist == "Script Band"
                  && sparseMain.artworkURL != nil && sparseMain.artworkData == nil, "AppleScript backs up missing adapter metadata")

        // Fallback: no adapter, only AppleScript players, no invented data
        let fallback = merge(nil, [spotify(playing: true), music])
        try check(fallback.map(\.id) == ["com.spotify.client", "com.apple.Music"], "no adapter: only AppleScript players")
        let fallbackMain = Service.snapshot(for: fallback[0], nowPlaying: nil, players: [spotify(playing: true), music])
        try check(fallbackMain.title == "Script Song" && fallbackMain.duration == nil && fallbackMain.elapsedTime == nil
                  && fallbackMain.artworkData == nil && fallbackMain.isPlaying, "no adapter: AppleScript metadata only")
        try check(merge(nil, []).isEmpty, "nothing running: no sources")
        try check(Service.snapshot(for: nil, nowPlaying: nil, players: []) == .idle, "no main source is idle")

        // An app without a media session (Moonlight) is never invented
        let withMoonlight = merge(chromeSession, [spotify(playing: false)])
        try check(!withMoonlight.contains(where: { $0.id.lowercased().contains("moonlight") }), "app without media session absent")
        try check(withMoonlight.count == 2, "only Now Playing app and AppleScript players")
        try check(!merge(nil, []).contains(where: { $0.id == "system-audio" || $0.id == "webkit-audio" }), "no synthetic sources")

        // Selection
        func source(_ id: String, playing: Bool) -> AudioSourceInfo {
            AudioSourceInfo(id: id, name: id, category: "media", icon: nil, isActive: false, isPlaying: playing)
        }
        let chromePlaying = source("com.google.Chrome", playing: true)
        let chromePaused = source("com.google.Chrome", playing: false)
        let spotifyPaused = source("com.spotify.client", playing: false)
        let spotifyPlaying = source("com.spotify.client", playing: true)
        let musicPaused = source("com.apple.Music", playing: false)
        let musicPlaying = source("com.apple.Music", playing: true)
        let np = "com.google.Chrome"

        try check(Service.mainSource(selected: nil, sources: [chromePaused, spotifyPlaying], nowPlayingID: np) == np, "auto: Now Playing app first")
        try check(Service.mainSource(selected: nil, sources: [spotifyPaused, musicPlaying], nowPlayingID: nil) == "com.apple.Music", "auto: playing AppleScript player next")
        try check(Service.mainSource(selected: nil, sources: [spotifyPaused, musicPaused], nowPlayingID: nil) == "com.spotify.client", "auto: paused AppleScript player last")
        try check(Service.mainSource(selected: nil, sources: [], nowPlayingID: nil) == nil, "auto: idle with no sources")
        try check(Service.mainSource(selected: "com.spotify.client", selectionWasPlaying: false,
                                     sources: [chromePlaying, spotifyPaused], nowPlayingID: np) == "com.spotify.client",
                  "clicked paused source stays main while another plays")
        try check(Service.retainedSelection("com.spotify.client", selectionWasPlaying: true,
                                            sources: [chromePlaying, spotifyPaused]) == nil,
                  "selection that played and stopped while another plays is cleared")
        try check(Service.mainSource(selected: "com.spotify.client", selectionWasPlaying: true,
                                     sources: [chromePlaying, spotifyPaused], nowPlayingID: np) == np,
                  "cleared selection falls back to the Now Playing app")
        try check(Service.retainedSelection("com.spotify.client", selectionWasPlaying: true,
                                            sources: [chromePaused, spotifyPaused]) == "com.spotify.client",
                  "stopped selection holds when nothing else plays")
        try check(Service.retainedSelection("com.spotify.client", sources: [chromePlaying, spotifyPlaying]) == "com.spotify.client", "playing selection holds")
        try check(Service.retainedSelection("com.gone.app", selectionWasPlaying: false, sources: [chromePlaying]) == nil, "vanished selection cleared")

        // Routing
        try check(Service.route(for: np, nowPlayingID: np) == .adapter(expectedOwner: np), "Now Playing app uses the adapter, bound to its owner")
        try check(Service.route(for: "com.spotify.client", nowPlayingID: "com.spotify.client")
                  == .adapter(expectedOwner: "com.spotify.client"), "Now Playing Spotify uses the adapter, bound to Spotify")
        try check(Service.route(for: np, nowPlayingID: chromeSession.ownerBundleIdentifier) == .adapter(expectedOwner: "com.google.Chrome"),
                  "expected owner is the parent app, not the helper")
        try check(Service.route(for: "com.spotify.client", nowPlayingID: np) == .appleScript("com.spotify.client"), "Spotify not Now Playing uses AppleScript")
        try check(Service.route(for: "com.apple.Music", nowPlayingID: nil) == .appleScript("com.apple.Music"), "Music without adapter uses AppleScript")
        guard case .unavailable(let reason) = Service.route(for: "com.example.Radio", nowPlayingID: np) else {
            throw Failure.check("other app that is not Now Playing has no command route")
        }
        try check(reason == "This app can only be controlled while it is the Mac's Now Playing app.", "unavailable reason")
        try check(Service.route(for: "com.example.Radio", nowPlayingID: nil) == .unavailable(reason), "no adapter: other app has no route")
        try check(Service.route(for: nil, nowPlayingID: np) == nil, "no main source has no route")

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
        try check(source("a", playing: true) == AudioSourceInfo(id: "a", name: "a", category: "media", icon: NSImage(), isActive: false, isPlaying: true), "equality ignores icon")
        try check(source("a", playing: true) != source("a", playing: false), "equality tracks playing state")
    }
}
