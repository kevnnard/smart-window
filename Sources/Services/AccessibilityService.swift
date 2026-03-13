import AppKit
import Foundation

// MARK: - AccessibilityService

/// Low-level wrapper around macOS Accessibility API (AXUIElement).
/// Handles permission checks and raw window enumeration.
final class AccessibilityService {

    static let shared = AccessibilityService()

    private init() {}

    // MARK: - Permission Check

    /// Returns `true` if the app has Accessibility permissions.
    var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permissions via System Preferences.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Window Enumeration

    /// Fetches all visible windows from all running applications.
    func getAllWindows() -> [WindowInfo] {
        guard isAccessibilityEnabled else { return [] }

        var allWindows: [WindowInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let windows = getWindows(for: appElement, app: app)
            allWindows.append(contentsOf: windows)
        }

        return allWindows
    }

    /// Fetches windows for a specific application.
    private func getWindows(for appElement: AXUIElement, app: NSRunningApplication) -> [WindowInfo] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windowList = windowsRef as? [AXUIElement] else {
            return []
        }

        return windowList.compactMap { windowElement in
            createWindowInfo(from: windowElement, app: app)
        }
    }

    /// Creates a `WindowInfo` from an AXUIElement window.
    private func createWindowInfo(from element: AXUIElement, app: NSRunningApplication) -> WindowInfo? {
        let title = getStringAttribute(element, attribute: kAXTitleAttribute) ?? ""
        let isMinimized = getBoolAttribute(element, attribute: kAXMinimizedAttribute)
        let position = getPointAttribute(element, attribute: kAXPositionAttribute)
        let size = getSizeAttribute(element, attribute: kAXSizeAttribute)

        let frame = CGRect(
            origin: position ?? .zero,
            size: size ?? CGSize(width: 800, height: 600)
        )

        return WindowInfo(
            pid: app.processIdentifier,
            appName: app.localizedName ?? "Unknown",
            appBundleIdentifier: app.bundleIdentifier,
            title: title,
            icon: app.icon,
            isMinimized: isMinimized,
            isOnScreen: !isMinimized,
            frame: frame,
            axElement: element
        )
    }

    // MARK: - Window Actions

    /// Brings a window to the front (focuses it).
    func focusWindow(_ window: WindowInfo) {
        guard let axElement = window.axElement else { return }

        // Activate the owning application
        if let app = runningApplication(for: window.pid) {
            app.activate()
        }

        // Raise the specific window
        AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, true as CFTypeRef)

        // Unminimize if needed
        if window.isMinimized {
            AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }
    }

    /// Minimizes a window.
    func minimizeWindow(_ window: WindowInfo) {
        guard let axElement = window.axElement else { return }
        AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    }

    /// Closes a window.
    func closeWindow(_ window: WindowInfo) {
        guard let axElement = window.axElement else { return }

        var closeButton: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axElement, kAXCloseButtonAttribute as CFString, &closeButton)

        if result == .success, let button = closeButton {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    /// Returns whether the frontmost application's focused window is fullscreen.
    func isFrontmostWindowFullscreen() -> Bool {
        frontmostFullscreenScreenFrame() != nil
    }

    /// Returns the screen frame containing the frontmost fullscreen window, if any.
    func frontmostFullscreenScreenFrame() -> CGRect? {
        guard isAccessibilityEnabled,
              let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )

        guard result == .success,
              let focusedWindowRef else {
            return nil
        }

        let focusedWindow = focusedWindowRef as! AXUIElement
        guard getBoolAttribute(focusedWindow, attribute: "AXFullScreen") else {
            return nil
        }

        let position = getPointAttribute(focusedWindow, attribute: kAXPositionAttribute) ?? .zero
        let size = getSizeAttribute(focusedWindow, attribute: kAXSizeAttribute) ?? .zero
        let windowFrame = CGRect(origin: position, size: size)

        if let matchingScreen = screenContainingMost(of: windowFrame) {
            return matchingScreen.frame
        }

        return nil
    }

    // MARK: - AX Attribute Helpers

    private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func getBoolAttribute(_ element: AXUIElement, attribute: String) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return false }
        return (value as? Bool) ?? false
    }

    private func getPointAttribute(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func getSizeAttribute(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        var size = CGSize.zero
        if AXValueGetValue(value as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    private func screenContainingMost(of frame: CGRect) -> NSScreen? {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        if let directMatch = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return directMatch
        }

        return NSScreen.screens.max { lhs, rhs in
            let lhsArea = intersectionArea(lhs.frame, frame)
            let rhsArea = intersectionArea(rhs.frame, frame)
            return lhsArea < rhsArea
        }
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    // MARK: - NSRunningApplication Helper

    private func runningApplication(for pid: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }
}
