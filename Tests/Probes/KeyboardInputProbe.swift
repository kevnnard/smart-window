import Carbon
import Foundation

@main
struct KeyboardInputProbe {
    struct Failure: Error { let message: String }

    @MainActor static func main() {
        do {
            try run()
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor static func run() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw Failure(message: message) }
        }
        func currentID() -> String {
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }
        let service = KeyboardInputService()
        let originalID = currentID()
        try require(service.selectedID == originalID, "Initial state differs from native macOS state")
        try require(!service.sources.isEmpty, "No configured keyboard sources available")
        try require(Set(service.sources.map(\.id)).count == service.sources.count, "Duplicate sources")
        try require(!service.sources.contains { $0.id == "com.apple.CharacterPaletteIM" }, "Emoji palette is not a keyboard layout")
        try require(KeyboardInputService.Source(id: "com.apple.keylayout.US", name: "U.S.").shortLabel == "US", "US label")
        try require(KeyboardInputService.Source(id: "com.apple.keylayout.LatinAmerican", name: "Latin American").shortLabel == "LAT", "Latin American label")
        try require(!service.select(id: "smartwindow.invalid-source"), "Invalid source must be rejected")
        try require(currentID() == originalID, "Invalid selection changed native keyboard")
        try require(service.selectionError != nil, "Rejected selection must provide an error")
        print("PASS: native source listing, labels, current state, and rejected selection")

        guard CommandLine.arguments.contains("--switch") else {
            print("SKIP: live switching (pass --switch to test and restore)")
            return
        }
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        // Restore even when a throwing check fails; never leave a test-selected layout active.
        defer { TISSelectInputSource(original) }
        guard let other = service.sources.first(where: { $0.id != originalID }) else {
            throw Failure(message: "Live switch requires two configured sources")
        }
        try require(service.select(id: other.id), "Selecting configured source failed")
        try require(currentID() == other.id, "Selection did not reach macOS")
        try require(service.selectedID == other.id, "Service did not update after selection")
        try require(service.selectionError == nil, "Successful selection did not clear error")
        try require(TISSelectInputSource(original) == noErr, "Native restoration failed")
        // Native selection simulates a change from the system Input menu. Pump notifications.
        let deadline = Date().addingTimeInterval(2)
        while service.selectedID != originalID && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try require(currentID() == originalID, "Original source was not restored")
        try require(service.selectedID == originalID, "External native change did not synchronize")
        print("PASS: live selection, native change notification, and original keyboard restored")
    }
}
