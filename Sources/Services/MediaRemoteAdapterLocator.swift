import Foundation

/// Finds the vendored mediaremote-adapter (perl script + framework), our
/// media sessions helper (perl runner + dylib) and the parent guard that
/// ends the adapter stream when SmartWindow dies, which `scripts/install-app.sh`
/// copies into the app bundle, or that `scripts/build-mediaremote-adapter.sh`
/// leaves in `.build/` for debug runs.
enum MediaRemoteAdapterLocator {
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"
    static let sessionsRunnerName = "media-sessions.pl"
    static let sessionsHelperName = "libMediaSessionsHelper.dylib"
    static let parentGuardName = "parent-guard.pl"

    /// Absolute, normalized URLs of every helper file, all from one directory.
    struct Files: Equatable {
        let script: URL
        let framework: URL
        let sessionsRunner: URL
        let sessionsHelper: URL
        let parentGuard: URL
    }

    /// Returns absolute, normalized URLs for the first candidate directory that
    /// contains both the script and the framework:
    /// 1. `<bundle Resources>/MediaRemoteAdapter/`
    /// 2. `<executable dir>/../mediaremote-adapter/` (`.build/debug/SmartWindow`)
    /// 3. `<executable dir>/../../mediaremote-adapter/` (`.build/<triple>/debug/SmartWindow`)
    /// 4. `<executable dir>/../../../mediaremote-adapter/` (`.build/out/Products/Debug/SmartWindow`)
    static func locate(
        bundleResourceURL: URL?,
        executableURL: URL?,
        fileExists: (String) -> Bool
    ) -> (script: URL, framework: URL)? {
        for dir in candidates(bundleResourceURL: bundleResourceURL, executableURL: executableURL) {
            let script = dir.appendingPathComponent(scriptName, isDirectory: false)
            let framework = dir.appendingPathComponent(frameworkName, isDirectory: true)
            if fileExists(script.path) && fileExists(framework.path) {
                return (script, framework)
            }
        }
        return nil
    }

    /// Same candidate directories and order as `locate`, but a directory only
    /// matches when the adapter files, the media sessions helper files and the
    /// parent guard all exist.
    static func locateAll(
        bundleResourceURL: URL?,
        executableURL: URL?,
        fileExists: (String) -> Bool
    ) -> Files? {
        for dir in candidates(bundleResourceURL: bundleResourceURL, executableURL: executableURL) {
            let files = Files(
                script: dir.appendingPathComponent(scriptName, isDirectory: false),
                framework: dir.appendingPathComponent(frameworkName, isDirectory: true),
                sessionsRunner: dir.appendingPathComponent(sessionsRunnerName, isDirectory: false),
                sessionsHelper: dir.appendingPathComponent(sessionsHelperName, isDirectory: false),
                parentGuard: dir.appendingPathComponent(parentGuardName, isDirectory: false)
            )
            if [files.script, files.framework, files.sessionsRunner, files.sessionsHelper, files.parentGuard]
                .allSatisfy({ fileExists($0.path) }) {
                return files
            }
        }
        return nil
    }

    /// Same candidate directories and order as `locate`; a directory matches when the
    /// adapter files and the parent guard exist (the stream never runs unguarded).
    static func locateStream(
        bundleResourceURL: URL?,
        executableURL: URL?,
        fileExists: (String) -> Bool
    ) -> (script: URL, framework: URL, parentGuard: URL)? {
        for dir in candidates(bundleResourceURL: bundleResourceURL, executableURL: executableURL) {
            let script = dir.appendingPathComponent(scriptName, isDirectory: false)
            let framework = dir.appendingPathComponent(frameworkName, isDirectory: true)
            let parentGuard = dir.appendingPathComponent(parentGuardName, isDirectory: false)
            if fileExists(script.path) && fileExists(framework.path) && fileExists(parentGuard.path) {
                return (script, framework, parentGuard)
            }
        }
        return nil
    }

    static func current() -> (script: URL, framework: URL)? {
        locate(
            bundleResourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    static func currentStream() -> (script: URL, framework: URL, parentGuard: URL)? {
        locateStream(
            bundleResourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    static func currentAll() -> Files? {
        locateAll(
            bundleResourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    private static func candidates(bundleResourceURL: URL?, executableURL: URL?) -> [URL] {
        var candidates: [URL] = []
        if let resources = bundleResourceURL {
            candidates.append(resources.appendingPathComponent("MediaRemoteAdapter", isDirectory: true))
        }
        if let executable = executableURL {
            let dir = executable.deletingLastPathComponent()
            candidates.append(dir.appendingPathComponent("../mediaremote-adapter", isDirectory: true))
            candidates.append(dir.appendingPathComponent("../../mediaremote-adapter", isDirectory: true))
            candidates.append(dir.appendingPathComponent("../../../mediaremote-adapter", isDirectory: true))
        }
        return candidates.map { $0.absoluteURL.standardizedFileURL }
    }
}
