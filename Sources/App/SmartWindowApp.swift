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
    }
}

// MARK: - SmartWindowDelegate

/// App delegate that boots the tab bar on launch.
@MainActor
final class SmartWindowDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static weak var shared: SmartWindowDelegate?

    let windowManager = WindowManager.shared
    let overlayController = OverlayPanelController()
    let hotKeyService = HotKeyService.shared
    let systemMonitor = SystemMonitorService()
    let nowPlaying = NowPlayingService()
    let notchController = NotchController()
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindowController: NSWindowController?

    override init() {
        super.init()
        SmartWindowDelegate.shared = self
    }

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
        
        notchController.show()

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

    @objc func showSettingsWindow(_ sender: Any?) {
        let controller = settingsWindowController ?? makeSettingsWindowController()
        settingsWindowController = controller
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let rootView = SettingsView()
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SmartWindow Settings"
        window.setContentSize(NSSize(width: 460, height: 520))
        window.minSize = NSSize(width: 460, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false

        return NSWindowController(window: window)
    }
}
