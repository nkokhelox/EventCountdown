import AppKit

enum MenuBarPanelMetrics {
    static let panelWidth: CGFloat = 340
    static let bottomInset: CGFloat = 8

    static func maxPanelHeight(for screen: NSScreen? = NSScreen.main) -> CGFloat {
        guard let screen else { return 560 }
        return screen.visibleFrame.height - bottomInset
    }
}
