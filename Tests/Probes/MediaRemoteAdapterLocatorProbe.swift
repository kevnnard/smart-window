import Foundation

@main
struct MediaRemoteAdapterLocatorProbe {
    enum Failure: Error { case check(String) }
    static func main() {
        do { try run(); print("PASS: MediaRemote adapter and media sessions helper lookup for app bundles and debug runs") }
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

        for executable in [".build/debug/SmartWindow", ".build/arm64-apple-macosx/debug/SmartWindow",
                           ".build/out/Products/Debug/SmartWindow"] {
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

        try runSessionsHelper(root: root, resources: resources, bundled: bundled, debugAdapter: debugAdapter)
    }

    static func runSessionsHelper(root: String, resources: URL, bundled: String, debugAdapter: String) throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        let names = ["mediaremote-adapter.pl", "MediaRemoteAdapter.framework",
                     "media-sessions.pl", "libMediaSessionsHelper.dylib"]
        let all = Set([bundled, debugAdapter].flatMap { dir in names.map { "\(dir)/\($0)" } })
        let debugOnly = all.filter { $0.hasPrefix(debugAdapter) }

        let appBundle = MediaRemoteAdapterLocator.locateAll(
            bundleResourceURL: resources,
            executableURL: URL(fileURLWithPath: "\(root)/.build/debug/SmartWindow"),
            fileExists: { all.contains($0) })
        try check(appBundle?.sessionsRunner.path == "\(bundled)/media-sessions.pl", "app bundle sessions runner wins")
        try check(appBundle?.sessionsHelper.path == "\(bundled)/libMediaSessionsHelper.dylib", "app bundle sessions helper wins")
        try check(appBundle?.script.path == "\(bundled)/mediaremote-adapter.pl", "app bundle script in locateAll")
        try check(appBundle?.framework.path == "\(bundled)/MediaRemoteAdapter.framework", "app bundle framework in locateAll")

        for executable in [".build/debug/SmartWindow", ".build/arm64-apple-macosx/debug/SmartWindow",
                           ".build/out/Products/Debug/SmartWindow"] {
            let debug = MediaRemoteAdapterLocator.locateAll(
                bundleResourceURL: URL(fileURLWithPath: "\(root)/.build/debug"),
                executableURL: URL(fileURLWithPath: "\(root)/\(executable)"),
                fileExists: { debugOnly.contains($0) })
            try check(debug?.sessionsRunner.path == "\(debugAdapter)/media-sessions.pl", "debug sessions runner from \(executable)")
            try check(debug?.sessionsHelper.path == "\(debugAdapter)/libMediaSessionsHelper.dylib", "debug sessions helper from \(executable)")
            for url in [debug?.script, debug?.framework, debug?.sessionsRunner, debug?.sessionsHelper].compactMap({ $0 }) {
                try check(url.path.hasPrefix("/") && !url.path.contains(".."), "absolute normalized path \(url.path)")
            }
        }

        // A bundle directory missing any one file is skipped for the next candidate.
        for missing in names {
            let found = MediaRemoteAdapterLocator.locateAll(
                bundleResourceURL: resources,
                executableURL: URL(fileURLWithPath: "\(root)/.build/out/Products/Debug/SmartWindow"),
                fileExists: { all.contains($0) && $0 != "\(bundled)/\(missing)" })
            try check(found?.sessionsHelper.path == "\(debugAdapter)/libMediaSessionsHelper.dylib",
                      "bundle without \(missing) falls through to debug")
            try check(MediaRemoteAdapterLocator.locateAll(
                bundleResourceURL: resources, executableURL: nil,
                fileExists: { all.contains($0) && $0 != "\(bundled)/\(missing)" }) == nil,
                      "bundle without \(missing) is not a match")
        }

        // The adapter-only lookup keeps working without the sessions helper.
        let adapterOnly: Set<String> = ["\(bundled)/mediaremote-adapter.pl", "\(bundled)/MediaRemoteAdapter.framework"]
        try check(MediaRemoteAdapterLocator.locate(
            bundleResourceURL: resources, executableURL: nil,
            fileExists: { adapterOnly.contains($0) })?.script.path == "\(bundled)/mediaremote-adapter.pl",
                  "locate ignores the sessions helper")
        try check(MediaRemoteAdapterLocator.locateAll(
            bundleResourceURL: resources, executableURL: nil,
            fileExists: { adapterOnly.contains($0) }) == nil, "locateAll needs the sessions helper")
    }
}
