import SwiftUI

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var overlayController: OverlayPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            windowsSection

            Divider()

            actionsSection

            Divider()

            appSection
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.53, blue: 0.35),
                                Color(red: 0.12, green: 0.36, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)

                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SmartWindow")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(windowManager.windows.count) windows detected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Windows")

            if windowManager.windows.isEmpty {
                HStack {
                    Spacer()
                    Text("No windows detected")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(windowManager.windows.prefix(12)) { window in
                            windowRow(window)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(.top, 8)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Quick Actions")

            menuButton(
                icon: overlayController.isVisible ? "eye.slash" : "eye",
                title: overlayController.isVisible ? "Hide Tab Bar" : "Show Tab Bar",
                shortcut: "⌥Esc"
            ) {
                overlayController.toggle()
            }

            menuButton(icon: "arrow.clockwise", title: "Refresh Windows") {
                windowManager.refresh()
            }

            menuButton(icon: "gearshape", title: "Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(.vertical, 8)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("App")

            menuButton(icon: "power", title: "Quit SmartWindow", tint: .red) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    private func windowRow(_ window: WindowInfo) -> some View {
        Button {
            windowManager.focus(window)
        } label: {
            HStack(spacing: 10) {
                if let icon = window.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }

                Text(window.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                if window.isMinimized {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func menuButton(
        icon: String,
        title: String,
        shortcut: String? = nil,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(tint)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
