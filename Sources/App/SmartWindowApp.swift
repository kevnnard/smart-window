import SwiftUI
import Combine

// MARK: - SmartWindowApp

@main
struct SmartWindowApp: App {
    @NSApplicationDelegateAdaptor(SmartWindowDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon — minimal controls
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.windowManager)
                .environmentObject(appDelegate.overlayController)
        } label: {
            Image(systemName: "rectangle.split.3x1")
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
        }
    }
}

// MARK: - SmartWindowDelegate

/// App delegate that boots the tab bar on launch.
@MainActor
final class SmartWindowDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windowManager = WindowManager.shared
    let overlayController = OverlayPanelController()
    let hotKeyService = HotKeyService.shared
    let systemMonitor = SystemMonitorService()
    let nowPlaying = NowPlayingService()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu-bar-only app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Check accessibility
        if !windowManager.isAccessibilityEnabled {
            windowManager.requestPermissionAndStart()
        }

        // Show the tab bar immediately
        overlayController.systemMonitor = systemMonitor
        overlayController.nowPlaying = nowPlaying
        overlayController.show()

        windowManager.$fullscreenScreenFrame
            .removeDuplicates()
            .sink { [weak self] frame in
                self?.overlayController.setSuppressedScreenFrame(frame)
            }
            .store(in: &cancellables)

        // Setup hotkeys
        hotKeyService.onToggleOverlay = { [weak self] in
            self?.overlayController.toggle()
        }
        hotKeyService.onNextWindow = { [weak self] in
            self?.windowManager.focusNextWindow()
        }
        hotKeyService.onPreviousWindow = { [weak self] in
            self?.windowManager.focusPreviousWindow()
        }
        hotKeyService.onSwitchToWindow = { [weak self] index in
            self?.windowManager.focusWindow(at: index)
        }
        hotKeyService.registerHotKeys()

        // Listen for screen changes to reposition bar
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.overlayController.repositionIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyService.unregisterHotKeys()
    }
}
