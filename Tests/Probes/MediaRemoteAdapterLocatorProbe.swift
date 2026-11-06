import Foundation

@main
struct MediaRemoteAdapterLocatorProbe {
    enum Failure: Error { case check(String) }
    static func main() {
        do { try run(); print("PASS: MediaRemote adapter lookup for app bundles and debug runs") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        let root = "/Users/me/smart-window"
        let resources = URL(fileURLWithPath: "/Applications/SmartWindow.app/Contents/Resources")
        let bundled = "\(resources.path)/MediaRemoteAdapter"
        let debugAdapter = "\(root)/.build/mediaremote-adapter"
        let all: Set<String> = [
            "\(bundled)/mediaremote-adapter.pl", "\(bundled)/MediaRemoteAdapter.framework",
            "\(debugAdapter)/mediaremote-adapter.pl", "\(debugAdapter)/MediaRemoteAdapter.framework",
        ]
        let debugOnly = all.filter { $0.hasPrefix(debugAdapter) }

        let appBundle = MediaRemoteAdapterLocator.locate(
            bundleResourceURL: resources,
            executableURL: URL(fileURLWithPath: "\(root)/.build/debug/SmartWindow"),
            fileExists: { all.contains($0) })
        try check(appBundle?.script.path == "\(bundled)/mediaremote-adapter.pl", "app bundle script wins")
        try check(appBundle?.framework.path == "\(bundled)/MediaRemoteAdapter.framework", "app bundle framework wins")

        for executable in [".build/debug/SmartWindow", ".build/arm64-apple-macosx/debug/SmartWindow"] {
            let debug = MediaRemoteAdapterLocator.locate(
                bundleResourceURL: URL(fileURLWithPath: "\(root)/.build/debug"),
                executableURL: URL(fileURLWithPath: "\(root)/\(executable)"),
                fileExists: { debugOnly.contains($0) })
            try check(debug?.script.path == "\(debugAdapter)/mediaremote-adapter.pl", "debug script from \(executable)")
            try check(debug?.framework.path == "\(debugAdapter)/MediaRemoteAdapter.framework", "debug framework from \(executable)")
            for url in [debug?.script, debug?.framework].compactMap({ $0 }) {
                try check(url.path.hasPrefix("/") && !url.path.contains(".."), "absolute normalized path \(url.path)")
            }
        }

        let partial = MediaRemoteAdapterLocator.locate(
            bundleResourceURL: resources, executableURL: nil,
            fileExists: { $0 == "\(bundled)/mediaremote-adapter.pl" })
        try check(partial == nil, "script without framework is not a match")
        try check(MediaRemoteAdapterLocator.locate(
            bundleResourceURL: resources,
            executableURL: URL(fileURLWithPath: "\(root)/.build/debug/SmartWindow"),
            fileExists: { _ in false }) == nil, "nothing found returns nil")
        try check(MediaRemoteAdapterLocator.locate(
            bundleResourceURL: nil, executableURL: nil, fileExists: { _ in true }) == nil, "no anchors returns nil")
    }
}
