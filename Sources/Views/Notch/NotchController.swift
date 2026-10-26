import Cocoa
import SwiftUI

@MainActor
final class NotchController: NSObject, ObservableObject {
    /// Panels for each screen - keyed by screen's unique identifier
    private var panels: [CGDirectDisplayID: NotchOverlayWindow] = [:]
    
    /// Shared NowPlayingService so all notch windows show the same info
    private let nowPlayingService = NowPlayingService()
    
    override init() {
        super.init()
    }
    
    func show() {
        // Safety check: ensure screens are available
        guard !NSScreen.screens.isEmpty else {
            print("[NotchController] No screens available, skipping panel creation")
            return
        }
        
        if panels.isEmpty {
            createPanels()
        }
        
        print("[NotchController] Showing \(panels.count) notch panel(s)")
        for panel in panels.values {
            panel.orderFront(nil)
        }
    }
    
    func hide() {
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
                panel.orderFront(nil)
            }
            
            // Reposition existing or new panel
            if let panel = panels[displayID] {
                positionPanel(panel, on: screen)
            }
        }
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
            rootView: NotchView(nowPlaying: nowPlayingService, layout: layout)
        )
        return panel
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
