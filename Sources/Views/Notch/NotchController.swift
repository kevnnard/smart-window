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
    /// Pointer monitors: global while the pointer is over other apps (the notch window then ignores
    /// the mouse), local while it is over the notch.
    private var pointerMonitors: [Any] = []
    
    override init() {
        super.init()
        DisplayPreferences.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // A per-display notch size or Expanded width may have changed, so resize as well.
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

        // A volume or brightness change shows the notch even when nothing is playing. Hover keeps
        // the compact area, so the wider wings do not open the drawer under a resting pointer.
        SystemHUDState.shared.$event
            .map { $0 != nil }
            .removeDuplicates()
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
        
        migrateMainDisplayOnly()
        if panels.isEmpty {
            createPanels()
        }
        startPointerMonitors()
        
        print("[NotchController] Showing \(panels.count) notch panel(s)")
        refreshVisibility()
    }

    /// "Main display only" is now Show notch off on each other display; see AppSettings.
    private func migrateMainDisplayOnly() {
        let preferences = DisplayPreferences.shared
        let connected = DisplayIdentity.connectedDisplays().map(\.key)
        AppSettings.migrateMainDisplayOnly(
            preferences: preferences,
            primaryKey: NSScreen.primary.flatMap(DisplayIdentity.key(for:)),
            knownKeys: connected + Array(preferences.displayInfo.keys) + Array(preferences.overrides.keys))
    }

    private func refreshVisibility() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let panel = panels[id] else { continue }

            // Show notch and show when nothing is playing of this display: its own values, else Default.
            let notch = DisplayPreferences.shared.effectiveSettings(for: DisplayIdentity.key(for: screen))
            let showsHUD = SystemHUDState.shared.event != nil
            let shouldShow = isVisible && notch.showNotch
                && (notch.showWhenIdle || nowPlayingService.hasPlayer || showsHUD)

            if shouldShow {
                panel.orderFront(nil)
            } else {
                panel.orderOut(nil)
            }
        }
        // A panel that just hid releases hover and clicks; one that appeared under the pointer takes them.
        updatePointer()
    }
    
    /// Switches each notch window between taking clicks (pointer over the drawn notch) and letting
    /// them through to the window below.
    private func startPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updatePointer()
        }) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updatePointer()
            return event
        }) {
            pointerMonitors.append(local)
        }
        updatePointer()
    }

    private func updatePointer() {
        let location = NSEvent.mouseLocation
        for panel in panels.values {
            (panel.contentView as? NotchHostingView<NotchView>)?.updatePointer(at: location)
        }
    }

    func hide() {
        isVisible = false
        for panel in panels.values {
            panel.orderOut(nil)
        }
        updatePointer()
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
                    // The drawn area changed under a resting pointer.
                    self?.updatePointer()
                }
            }
        return panel
    }

    /// Positions a panel centered at the top of the given screen. The window always has the
    /// open-drawer size, so opening and closing never resize it (a resize redraws late and moves
    /// the compact row); it ignores the mouse outside the drawn part (`updatePointer`).
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
        (panel.contentView as? NotchHostingView<NotchView>)?.updatePointer(at: NSEvent.mouseLocation)
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
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setPointerInside(false)
    }

    private var pointerInside = false

    /// The window always has the open drawer's size, and a transparent window still takes the
    /// clicks over it. So it ignores the mouse except over the drawn part, and follows the pointer
    /// (screen coordinates) to switch. While it ignores the mouse, its tracking area gets no
    /// events, so this also reports hover.
    func updatePointer(at screenPoint: CGPoint) {
        guard let window else { return }
        let visible = hoverRect()
        let drawn = CGRect(x: window.frame.minX + visible.minX, y: window.frame.maxY - visible.maxY,
                           width: visible.width, height: visible.height)
        // A hidden notch (ordered out) draws nothing, so it never takes the pointer.
        let inside = window.isVisible && drawn.contains(screenPoint)
        if window.ignoresMouseEvents == inside {
            window.ignoresMouseEvents = !inside
        }
        setPointerInside(inside)
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            panelState.pointerEntered()
        } else {
            panelState.pointerExited()
        }
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
        // Lets clicks through until the pointer is over the drawn notch (NotchHostingView.updatePointer).
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = true
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
