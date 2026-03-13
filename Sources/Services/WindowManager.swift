import AppKit
import Combine
import Foundation

// MARK: - WindowManager

/// High-level window management service.
/// Observes running applications, tracks window state, and publishes updates.
@MainActor
final class WindowManager: ObservableObject {

    static let shared = WindowManager()

    // MARK: - Published State

    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var activeWindowId: UUID?
    @Published private(set) var isAccessibilityEnabled: Bool = false
    @Published private(set) var isFrontmostWindowFullscreen: Bool = false
    @Published private(set) var fullscreenScreenFrame: CGRect?

    // MARK: - Dependencies

    private let accessibilityService = AccessibilityService.shared
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    // MARK: - Configuration

    private let refreshInterval: TimeInterval = 1.0

    private init() {
        isAccessibilityEnabled = accessibilityService.isAccessibilityEnabled
        setupWorkspaceObservers()

        if isAccessibilityEnabled {
            startMonitoring()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    // MARK: - Public API

    /// Requests accessibility permission and starts monitoring once granted.
    func requestPermissionAndStart() {
        accessibilityService.requestAccessibilityPermission()

        // Poll until permission is granted
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                if self.accessibilityService.isAccessibilityEnabled {
                    self.isAccessibilityEnabled = true
                    self.startMonitoring()
                    timer.invalidate()
                }
            }
        }
    }

    /// Refreshes the window list immediately.
    func refresh() {
        let newWindows = accessibilityService.getAllWindows()
        self.windows = newWindows
        detectActiveWindow()
        fullscreenScreenFrame = accessibilityService.frontmostFullscreenScreenFrame()
        isFrontmostWindowFullscreen = fullscreenScreenFrame != nil
    }

    /// Focuses a specific window by bringing it to the front.
    func focus(_ window: WindowInfo) {
        accessibilityService.focusWindow(window)
        activeWindowId = window.id

        // Small delay then refresh to reflect new state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }

    /// Minimizes a window.
    func minimize(_ window: WindowInfo) {
        accessibilityService.minimizeWindow(window)
        refresh()
    }

    /// Closes a window.
    func close(_ window: WindowInfo) {
        accessibilityService.closeWindow(window)

        // Remove from list immediately for snappy UI
        windows.removeAll { $0.id == window.id }

        // Full refresh after a beat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    /// Returns windows grouped by application.
    func windowsByApp() -> [WindowGroup] {
        let grouped = Dictionary(grouping: windows) { $0.appBundleIdentifier ?? $0.appName }

        return grouped.map { (key, wins) in
            WindowGroup(
                id: key,
                appName: wins.first?.appName ?? key,
                icon: wins.first?.icon,
                windows: wins
            )
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    /// Focuses a window by its index in the list (0-based). Used for ⌥1-⌥9.
    func focusWindow(at index: Int) {
        guard index >= 0, index < windows.count else { return }
        focus(windows[index])
    }

    /// Cycles to the next window in the list.
    func focusNextWindow() {
        guard !windows.isEmpty else { return }

        if let currentId = activeWindowId,
           let currentIndex = windows.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = (currentIndex + 1) % windows.count
            focus(windows[nextIndex])
        } else {
            focus(windows[0])
        }
    }

    /// Cycles to the previous window in the list.
    func focusPreviousWindow() {
        guard !windows.isEmpty else { return }

        if let currentId = activeWindowId,
           let currentIndex = windows.firstIndex(where: { $0.id == currentId }) {
            let prevIndex = (currentIndex - 1 + windows.count) % windows.count
            focus(windows[prevIndex])
        } else {
            focus(windows.last!)
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func detectActiveWindow() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        if let frontWindow = windows.first(where: {
            $0.pid == frontApp.processIdentifier && $0.isOnScreen
        }) {
            activeWindowId = frontWindow.id
        }
    }

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        let activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        let launchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        let terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        workspaceObservers = [activateObserver, launchObserver, terminateObserver]
    }
}
