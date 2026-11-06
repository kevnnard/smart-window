import Foundation

/// Single owner of one notch panel's expanded state. The controller keeps one per display,
/// the view renders it, and the controller resizes the panel from it.
@MainActor
final class NotchPanelState: ObservableObject {
    @Published var isExpanded = false

    /// Grace period before collapsing after the pointer leaves, so the window resize
    /// cannot start an expand/collapse loop.
    static let collapseDelay: TimeInterval = 0.25

    private var collapseTask: Task<Void, Never>?

    func expand() {
        cancelCollapse()
        if !isExpanded { isExpanded = true }
    }

    func collapse() {
        cancelCollapse()
        if isExpanded { isExpanded = false }
    }

    func pointerEntered() {
        expand()
    }

    /// Collapses after `collapseDelay` unless the pointer comes back first.
    func pointerExited() {
        cancelCollapse()
        guard isExpanded else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.collapseDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}
