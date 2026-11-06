import Foundation

/// Finds the vendored mediaremote-adapter (perl script + framework) that
/// `scripts/install-app.sh` copies into the app bundle, or that
/// `scripts/build-mediaremote-adapter.sh` leaves in `.build/` for debug runs.
enum MediaRemoteAdapterLocator {
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"

    /// Returns absolute, normalized URLs for the first candidate directory that
    /// contains both the script and the framework:
    /// 1. `<bundle Resources>/MediaRemoteAdapter/`
    /// 2. `<executable dir>/../mediaremote-adapter/` (`.build/debug/SmartWindow`)
    /// 3. `<executable dir>/../../mediaremote-adapter/` (`.build/<triple>/debug/SmartWindow`)
    static func locate(
        bundleResourceURL: URL?,
        executableURL: URL?,
        fileExists: (String) -> Bool
    ) -> (script: URL, framework: URL)? {
        var candidates: [URL] = []
        if let resources = bundleResourceURL {
            candidates.append(resources.appendingPathComponent("MediaRemoteAdapter", isDirectory: true))
        }
        if let executable = executableURL {
            let dir = executable.deletingLastPathComponent()
            candidates.append(dir.appendingPathComponent("../mediaremote-adapter", isDirectory: true))
            candidates.append(dir.appendingPathComponent("../../mediaremote-adapter", isDirectory: true))
        }
        for candidate in candidates {
            let dir = candidate.absoluteURL.standardizedFileURL
            let script = dir.appendingPathComponent(scriptName, isDirectory: false)
            let framework = dir.appendingPathComponent(frameworkName, isDirectory: true)
            if fileExists(script.path) && fileExists(framework.path) {
                return (script, framework)
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
}
