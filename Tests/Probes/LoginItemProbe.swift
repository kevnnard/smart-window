import Foundation

@main
struct LoginItemProbe {
    enum Failure: Error { case check(String) }
    @MainActor static func main() {
        do { try run(); print("PASS: login item registration states and failures") }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) throws {
            if !value() { throw Failure.check(name) }
        }
        var state = LoginItemService.Status.disabled
        var registrations = 0
        var removals = 0
        var fail = false
        var approvals = false
        let service = LoginItemService(status: { state }, register: {
            if fail { throw Failure.check("native denial") }
            registrations += 1
            state = approvals ? .requiresApproval : .enabled
        }, unregister: {
            if fail { throw Failure.check("native denial") }
            removals += 1; state = .disabled
        })
        service.setEnabled(true)
        try check(service.status == .enabled && registrations == 1, "registers with macOS")
        service.setEnabled(false)
        try check(service.status == .disabled && removals == 1, "unregisters with macOS")
        approvals = true; service.setEnabled(true)
        try check(service.status == .requiresApproval && service.isEnabled, "approval is not reported as enabled registration")
        fail = true; service.setEnabled(false)
        try check(service.status == .requiresApproval && removals == 1 && service.errorMessage != nil, "failure preserves actual state")
        fail = false; service.setEnabled(false)
        try check(service.errorMessage == nil, "successful retry clears error")
        state = .unavailable
        service.setEnabled(true)
        try check(registrations == 2 && service.status == .unavailable, "unbundled state cannot register")
    }
}
