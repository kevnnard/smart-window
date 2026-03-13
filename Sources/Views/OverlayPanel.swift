import AppKit
import SwiftUI

// MARK: - Tab Bar Constants

enum TabBarConstants {
    /// Match the native menu bar height
    static var barHeight: CGFloat {
        guard let screen = NSScreen.main else { return 31 }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return max(menuBarHeight + 1, 26)
    }
}

struct TopBarScreenLayout {
    let totalWidth: CGFloat
    let leftRegionInset: CGFloat
    let leftRegionWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightRegionWidth: CGFloat
    let rightRegionInset: CGFloat

    var hasNotch: Bool { centerGapWidth > 0 }

    init(screen: NSScreen?) {
        guard let screen else {
            self.totalWidth = 0
            self.leftRegionInset = 0
            self.leftRegionWidth = 0
            self.centerGapWidth = 0
            self.rightRegionWidth = 0
            self.rightRegionInset = 0
            return
        }

        let screenFrame = screen.frame
        let fullWidth = screenFrame.width

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let leftInset = max(leftArea.minX - screenFrame.minX, 0)
            let leftWidth = max(leftArea.width, 0)
            let rightInset = max(screenFrame.maxX - rightArea.maxX, 0)
            let rightWidth = max(rightArea.width, 0)
            let centerWidth = max(rightArea.minX - leftArea.maxX, 0)

            if centerWidth > 0 {
                self.totalWidth = fullWidth
                self.leftRegionInset = leftInset
                self.leftRegionWidth = leftWidth
                self.centerGapWidth = centerWidth
                self.rightRegionWidth = rightWidth
                self.rightRegionInset = rightInset
                return
            }
        }

        self.totalWidth = fullWidth
        self.leftRegionInset = 0
        self.leftRegionWidth = fullWidth
        self.centerGapWidth = 0
        self.rightRegionWidth = 0
        self.rightRegionInset = 0
    }
}

// MARK: - OverlayPanel

/// Full-width dark panel that covers the macOS menu bar on one screen.
final class OverlayPanel: NSPanel {

    /// The screen this panel is associated with.
    weak var associatedScreen: NSScreen?

    init(contentRect: NSRect, screen: NSScreen?) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.associatedScreen = screen
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Visible on ALL desktops, don't appear in Cmd+Tab
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false
    }

    /// Force the window level AFTER creation — some macOS versions
    /// reset the level during init. Call this after orderFront.
    func forceLevel(_ lvl: Int) {
        level = NSWindow.Level(rawValue: lvl)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - OverlayPanelController

/// Creates and manages one polybar panel per active screen.
@MainActor
final class OverlayPanelController: ObservableObject {

    @Published var isVisible: Bool = false

    private var panels: [OverlayPanel] = []
    private var suppressedScreenFrame: CGRect?
    var systemMonitor: SystemMonitorService?
    var nowPlaying: NowPlayingService?

    func show() {
        rebuildPanels()
        isVisible = true

        // Double-check positions after a beat (some screen setups need this)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.repositionAllPanels()
        }
    }

    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func setSuppressedScreenFrame(_ frame: CGRect?) {
        guard suppressedScreenFrame != frame else { return }
        suppressedScreenFrame = frame

        guard isVisible else { return }
        applySuppressionState()
    }

    func repositionIfNeeded() {
        guard isVisible else { return }

        // Check if screens changed (added/removed monitors)
        let currentScreenCount = NSScreen.screens.count
        let panelCount = panels.count

        if currentScreenCount != panelCount {
            // Screens changed — rebuild everything
            rebuildPanels()
        } else {
            repositionAllPanels()
        }
    }

    // MARK: - Panel Lifecycle

    /// Tears down all existing panels and creates one per screen.
    private func rebuildPanels() {
        // Remove old panels
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()

        // Create one panel per screen
        let screens = NSScreen.screens
        let monitor = systemMonitor ?? SystemMonitorService()
        let playing = nowPlaying ?? NowPlayingService()

        for screen in screens {
            let frame = Self.panelFrame(for: screen)
            let panel = OverlayPanel(contentRect: frame, screen: screen)

            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 0

            let hostingView = NSHostingView(
                rootView: TabBarView(screen: screen)
                    .environmentObject(WindowManager.shared)
                    .environmentObject(self)
                    .environmentObject(monitor)
                    .environmentObject(playing)
            )
            hostingView.frame = effectView.bounds
            hostingView.autoresizingMask = [.width, .height]

            effectView.addSubview(hostingView)
            panel.contentView = effectView
            panel.orderFrontRegardless()
            panel.forceLevel(26)

            panels.append(panel)
        }

        applySuppressionState()

        let count = screens.count
        print("📐 SmartWindow: created \(count) panel(s) for \(count) screen(s)")
    }

    /// Repositions all existing panels to match current screen positions.
    private func repositionAllPanels() {
        for panel in panels {
            guard let screen = panel.associatedScreen else { continue }
            let frame = Self.panelFrame(for: screen)

            print("📐 SmartWindow panel: x=\(frame.origin.x) y=\(frame.origin.y) w=\(frame.width) h=\(frame.height) | screen.frame=\(screen.frame)")

            panel.setFrame(frame, display: true, animate: false)
            panel.forceLevel(26)
            if screen.frame != suppressedScreenFrame {
                panel.orderFrontRegardless()
            }
        }
    }

    private func applySuppressionState() {
        for panel in panels {
            guard let screen = panel.associatedScreen else { continue }
            if screen.frame == suppressedScreenFrame {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
                panel.forceLevel(26)
            }
        }
    }

    /// Calculates the panel frame for a given screen.
    private static func panelFrame(for screen: NSScreen) -> CGRect {
        let height = TabBarConstants.barHeight
        return CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
    }
}
