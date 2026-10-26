import Foundation

@main
struct NowPlayingControlsProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: Now Playing transport routing and preserved metadata") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        var scripts: [String] = []
        var refreshes = 0
        for id in ["com.spotify.client", "com.apple.Music"] {
            for action in [NowPlayingService.TransportAction.previous, .playPause, .next] {
                try NowPlayingService.send(action, bundleIdentifier: id, runningIDs: [id],
                    execute: { scripts.append($0) }, refresh: { refreshes += 1 })
                try check(scripts.last?.contains(action.rawValue) == true, "native command mapped")
                try check(scripts.last?.contains(id) == true, "known player targeted")
            }
        }
        try check(refreshes == 6 && scripts.count == 6, "successful command refreshes state")
        for id in ["unknown.player", "com.spotify.client"] {
            do {
                try NowPlayingService.send(.next, bundleIdentifier: id, runningIDs: [],
                    execute: { scripts.append($0) }, refresh: { refreshes += 1 })
                throw Failure.check("invalid or stopped player accepted")
            } catch is NowPlayingService.TransportError { }
        }
        try check(scripts.count == 6 && refreshes == 6, "rejected commands have no side effects")
        do {
            try NowPlayingService.send(.playPause, bundleIdentifier: "com.apple.Music", runningIDs: ["com.apple.Music"],
                execute: { _ in throw Failure.check("native failure") }, refresh: { refreshes += 1 })
            throw Failure.check("execution error swallowed")
        } catch Failure.check(let message) {
            try check(message == "native failure", "native error propagated")
        }
        try check(refreshes == 6, "failed command does not fabricate a state refresh")
        let paused = NowPlayingService.parse("PAUSED\nTrack\nArtist\nAlbum", bundleIdentifier: "com.spotify.client")
        try check(!paused.isPlaying && paused.title == "Track" && paused.bundleIdentifier == "com.spotify.client", "paused player retained")
        let empty = NowPlayingService.parse("PAUSED", bundleIdentifier: "com.apple.Music")
        try check(empty.title.isEmpty && empty.bundleIdentifier == "com.apple.Music", "running idle player retained")
    }
}
