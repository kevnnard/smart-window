import Foundation
import AppKit

@main
struct TailscaleProbe {
    @MainActor static func main() {
        func parse(_ text: String) -> TailscaleService.Snapshot {
            TailscaleService.parse(Data(text.utf8))
        }
        // Invalid output must never claim the VPN is off or connected.
        assert(parse("not json").backendState == "unavailable")
        assert(parse(#"{"BackendState":"Running","Self":{"Online":true}}"#).state == .connected)
        assert(parse(#"{"BackendState":"Running","Self":{"Online":false}}"#).state == .connecting)
        assert(parse(#"{"BackendState":"Stopped"}"#).state == .stopped)
        assert(TailscaleService.format(duration: 59) == "59s")
        assert(TailscaleService.format(duration: 60) == "1m")
        assert(TailscaleService.format(duration: 3660) == "1h 1m")
        assert(TailscaleService.format(duration: 86400) == "1d 0h")
        // These subprocesses are isolated fixtures, not the real Tailscale CLI.
        let start = ProcessInfo.processInfo.systemUptime
        let ignoredTerm = TailscaleService.runCLI(executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.15)
        assert(ignoredTerm.state == .unavailable)
        assert(ProcessInfo.processInfo.systemUptime - start < 1)

        let inheritedStart = ProcessInfo.processInfo.systemUptime
        let inheritedPipe = TailscaleService.runCLI(executable: "/bin/sh",
            arguments: ["-c", "sleep 1 & printf '%s' '{\"BackendState\":\"Stopped\"}'"], timeout: 0.15)
        assert(inheritedPipe.state == .stopped)
        assert(ProcessInfo.processInfo.systemUptime - inheritedStart < 0.8)
        let stopped = TailscaleService.runCLI(executable: "/bin/sh",
            arguments: ["-c", "printf '%s' '{\"BackendState\":\"Stopped\"}'"], timeout: 1)
        assert(stopped.state == .stopped)

        // Exercise the actual workspace sleep notification, without polling the VPN.
        let service = TailscaleService(monitoring: false)
        let online = parse(#"{"BackendState":"Running","Self":{"Online":true}}"#)
        service.apply(online)
        assert(service.connectedSince != nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        assert(service.connectedSince == nil)
        assert(service.state == .unavailable)
        print("PASS: Tailscale parsing, duration, bounded subprocesses, and sleep reset")
    }
}
