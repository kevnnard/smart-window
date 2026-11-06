import Cocoa
import SwiftUI
import Combine

@MainActor
final class NotchController: NSObject, ObservableObject {
    /// Panels for each screen - keyed by screen's unique identifier
    private var panels: [CGDirectDisplayID: NotchOverlayWindow] = [:]
    
    /// Shared NowPlayingService so all notch windows show the same info
    private let nowPlayingService = NowPlayingService()
    private var isVisible = false
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        DisplayPreferences.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)

        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionAll()
                self?.refreshVisibility()
            }
            .store(in: &cancellables)

        nowPlayingService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)
    }
    
    func show() {
        isVisible = true
        // Safety check: ensure screens are available
        guard !NSScreen.screens.isEmpty else {
            print("[NotchController] No screens available, skipping panel creation")
            return
        }
        
        if panels.isEmpty {
            createPanels()
        }
        
        print("[NotchController] Showing \(panels.count) notch panel(s)")
        refreshVisibility()
    }

    private func refreshVisibility() {
        let isMainOnly = !AppSettings.shared.notchShowOnAllDisplays
        let mainDisplayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let panel = panels[id] else { continue }

            if isMainOnly && id != mainDisplayID {
                panel.orderOut(nil)
                continue
            }

            let displayKey = DisplayIdentity.key(for: screen)
            let displayPrefAllowed = DisplayPreferences.shared.nowPlayingVisible(on: displayKey)
            let shouldShow = isVisible && displayPrefAllowed && (AppSettings.shared.notchAlwaysVisible || nowPlayingService.hasPlayer)

            if shouldShow {
                panel.orderFront(nil)
            } else {
                panel.orderOut(nil)
            }
        }
    }
    
    func hide() {
        isVisible = false
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }
    
    /// Creates a panel for each connected screen
    private func createPanels() {
        // Remove existing panels first
        panels.removeAll()
        
        // Safety check: ensure screens are available
        guard !NSScreen.screens.isEmpty else {
            print("[NotchController] No screens available for panel creation")
            return
        }
        
        print("[NotchController] Creating panels for \(NSScreen.screens.count) screen(s)")
        
        // Create a panel for EACH screen
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            let panel = makePanel(for: screen)
            panels[displayID] = panel
            
            // Position this panel on its screen
            positionPanel(panel, on: screen)
        }
        
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenChange()
            }
        }
        
        // Listen for space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionAll()
            }
        }
    }
    
    /// Handles screen configuration changes (monitors added/removed)
    private func handleScreenChange() {
        let currentScreens = Set(NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        })
        
        let existingPanels = Set(panels.keys)
        
        // Remove panels for disconnected screens
        for displayID in existingPanels.subtracting(currentScreens) {
            panels[displayID]?.orderOut(nil)
            panels.removeValue(forKey: displayID)
        }
        
        // Add panels for newly connected screens
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            if panels[displayID] == nil {
                let panel = makePanel(for: screen)
                panels[displayID] = panel
            }
            
            // Reposition existing or new panel
            if let panel = panels[displayID] {
                positionPanel(panel, on: screen)
            }
        }
        refreshVisibility()
    }
    
    /// Repositions all panels on their respective screens
    func repositionAll() {
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let panel = panels[displayID] else {
                continue
            }
            positionPanel(panel, on: screen)
        }
    }
    
    /// Builds a panel sized to the screen's notch geometry. All panels share the same NowPlayingService.
    private func makePanel(for screen: NSScreen) -> NotchOverlayWindow {
        let layout = NotchLayout.forScreen(screen)
        let panel = NotchOverlayWindow(
            contentRect: NSRect(origin: .zero, size: layout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(
            rootView: NotchView(
                nowPlaying: nowPlayingService,
                layout: layout,
                screen: screen,
                displayKey: DisplayIdentity.key(for: screen),
                onExpandChange: { [weak self] expanded in
                    self?.setExpanded(expanded, on: screen)
                }
            )
        )
        return panel
    }

    /// Dynamically expands or collapses the panel window frame to match the Dynamic Island state.
    func setExpanded(_ expanded: Bool, on screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let panel = panels[displayID] else { return }

        let screenFrame = screen.frame
        let layout = NotchLayout.forScreen(screen)
        let targetWidth = expanded ? max(layout.contentWidth, 440) : layout.contentWidth
        let targetHeight = expanded ? 180 + NotchLayout.bottomPadding : layout.panelSize.height
        let x = screenFrame.minX + (screenFrame.width - targetWidth) / 2
        let y = screenFrame.maxY - targetHeight

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: x, y: y, width: targetWidth, height: targetHeight), display: true)
        }
    }

    /// Positions a panel centered at the top of the given screen
    private func positionPanel(_ panel: NotchOverlayWindow, on screen: NSScreen) {
        let screenFrame = screen.frame
        
        panel.contentView?.layoutSubtreeIfNeeded()
        // Width hugs the physical notch plus a wing on each side (or a compact pill without a notch).
        let panelSize = NotchLayout.forScreen(screen).panelSize
        panel.setContentSize(panelSize)
        
        let x = screenFrame.minX + (screenFrame.width - panelSize.width) / 2
        
        // Place the window exactly at the top of the screen.
        let y = screenFrame.maxY - panelSize.height
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

class NotchOverlayWindow: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)
        
        // Window level: popUpMenu (101) works in both dev and signed builds
        self.level = .popUpMenu
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = false
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
