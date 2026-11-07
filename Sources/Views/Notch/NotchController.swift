import Cocoa
import SwiftUI
import Combine

@MainActor
final class NotchController: NSObject, ObservableObject {
    /// Panels for each screen - keyed by screen's unique identifier
    private var panels: [CGDirectDisplayID: NotchOverlayWindow] = [:]
    /// Expanded state of each panel; the single source of truth for its size.
    private var panelStates: [CGDirectDisplayID: NotchPanelState] = [:]
    private var panelObservers: [CGDirectDisplayID: AnyCancellable] = [:]
    
    /// Shared NowPlayingService so all notch windows show the same info
    private let nowPlayingService = NowPlayingService()
    private var isVisible = false
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        DisplayPreferences.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // A per-display notch size may have changed, so resize as well.
                self?.repositionAll()
                self?.refreshVisibility()
            }
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

        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let panel = panels[id] else { continue }

            if isMainOnly && !screen.isPrimary {
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
        panelStates.removeAll()
        panelObservers.removeAll()
        
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
            
            let panel = makePanel(for: screen, displayID: displayID)
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
            panelStates.removeValue(forKey: displayID)
            panelObservers.removeValue(forKey: displayID)
        }
        
        // Add panels for newly connected screens
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            if panels[displayID] == nil {
                let panel = makePanel(for: screen, displayID: displayID)
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
    private func makePanel(for screen: NSScreen, displayID: CGDirectDisplayID) -> NotchOverlayWindow {
        let layout = NotchLayout.forScreen(screen)
        let state = NotchPanelState()
        let panel = NotchOverlayWindow(
            contentRect: NSRect(origin: .zero, size: layout.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NotchHostingView(
            rootView: NotchView(
                nowPlaying: nowPlayingService,
                layout: layout,
                screen: screen,
                displayKey: DisplayIdentity.key(for: screen),
                panelState: state
            ),
            panelState: state,
            hoverRect: { [weak state] in
                NotchLayout.forScreen(screen).visibleRect(expanded: state?.isExpanded ?? false)
            }
        )
        panelStates[displayID] = state
        // @Published emits on willSet, so the new value is passed explicitly.
        panelObservers[displayID] = state.$isExpanded
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // The window never changes size; only the hover area follows the drawn part.
                // Next run loop turn: this sink runs in @Published's willSet.
                DispatchQueue.main.async {
                    (self?.panels[displayID]?.contentView as? NotchHostingView<NotchView>)?.refreshHoverArea()
                }
            }
        return panel
    }

    /// Positions a panel centered at the top of the given screen. The window always has the
    /// open-drawer size, so opening and closing never resize it (a resize redraws late and moves
    /// the compact row); the transparent part lets clicks through.
    private func positionPanel(_ panel: NotchOverlayWindow, on screen: NSScreen) {
        let panelSize = NotchLayout.forScreen(screen).windowSize
        let screenFrame = screen.frame
        let frame = NSRect(
            x: screenFrame.minX + (screenFrame.width - panelSize.width) / 2,
            // Place the window exactly at the top of the screen.
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )

        panel.setFrame(frame, display: true)
        (panel.contentView as? NotchHostingView<NotchView>)?.refreshHoverArea()
    }
}

/// Hosting view that reports pointer enter/exit to the panel state. AppKit tracking with
/// `.activeAlways` keeps hover working in the non-activating panel while the app is inactive.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private let panelState: NotchPanelState
    private var hoverArea: NSTrackingArea?
    /// The drawn part of the window, from its top-left corner (see `NotchLayout.visibleRect`).
    private let hoverRect: () -> CGRect

    init(rootView: Content, panelState: NotchPanelState, hoverRect: @escaping () -> CGRect) {
        self.panelState = panelState
        self.hoverRect = hoverRect
        super.init(rootView: rootView)
        // Only NotchController sizes the panel. By default the hosting view resizes its window to
        // the SwiftUI content, keeping the bottom-left corner fixed, so the window would grow up
        // off screen or drop its top edge whenever the drawer opens or closes.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the hover area after the drawer opens or closes or the window moves.
    func refreshHoverArea() {
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Only the compact pill opens the drawer. Do not advertise the transparent window
        // area or the expanded card's non-interactive background as clickable.
        guard !panelState.isExpanded else { return }
        addCursorRect(visibleInteractionRect, cursor: .pointingHand)
    }

    /// Layout geometry starts at the top-left. NSHostingView is flipped, so its coordinates
    /// already match; invert Y only for a non-flipped hosting view.
    private var visibleInteractionRect: NSRect {
        let visible = hoverRect()
        return NSRect(x: bounds.minX + visible.minX,
                      y: isFlipped ? bounds.minY + visible.minY : bounds.maxY - visible.maxY,
                      width: visible.width, height: visible.height).intersection(bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // Only the drawn pill or drawer counts as hover; the rest of the window is transparent.
        let area = NSTrackingArea(rect: visibleInteractionRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        panelState.pointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        panelState.pointerExited()
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
        self.acceptsMouseMovedEvents = true
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
