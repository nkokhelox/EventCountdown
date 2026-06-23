import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @Environment(AppModel.self) private var appModel
    let event: CalendarEvent?
    let emoji: String
    let needsAcknowledgment: Bool

    var body: some View {
        let _ = appModel.tick
        Text(labelText)
            .overlay {
                MenuBarHoverTooltip {
                    appModel.menuBarEvent?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            }
    }

    private var labelText: String {
        guard let event else { return "\(AppConstants.defaultEmoji) —" }
        if needsAcknowledgment {
            return "! \(emoji) now"
        }
        let remaining = CountdownFormatter.remaining(until: event.startDate, now: appModel.tick)
        let countdown = CountdownFormatter.format(remaining: remaining).menuBarText
        var text = "\(emoji) \(countdown)"
        if text.count > 28 {
            text = String(text.prefix(28))
        }
        return text
    }
}

// MARK: - Hover tooltip (Stats-style floating panel)

private struct MenuBarHoverTooltip: NSViewRepresentable {
    let titleProvider: () -> String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MenuBarHoverAnchorView {
        let view = MenuBarHoverAnchorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MenuBarHoverAnchorView, context: Context) {
        context.coordinator.titleProvider = titleProvider
        nsView.coordinator = context.coordinator
        nsView.scheduleTrackingRefresh()
    }

    final class Coordinator: NSObject {
        var titleProvider: () -> String = { "" }

        private let tooltipPanel = MenuBarTooltipPanel()
        private weak var trackedView: NSView?
        private var trackingArea: NSTrackingArea?
        private var hideWorkItem: DispatchWorkItem?
        private var clickMonitor: Any?
        private var mouseMovedMonitor: Any?
        private var hoverPollTimer: Timer?
        private var installAttempts = 0

        deinit {
            tearDownTracking()
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
            if let mouseMovedMonitor {
                NSEvent.removeMonitor(mouseMovedMonitor)
            }
            hoverPollTimer?.invalidate()
        }

        func scheduleTrackingRefresh(from anchor: NSView) {
            installAttempts = 0
            installTracking(from: anchor)
        }

        private func installTracking(from anchor: NSView) {
            guard let target = findStatusItemView(startingAt: anchor) else {
                guard installAttempts < 20 else { return }
                installAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak anchor] in
                    guard let self, let anchor else { return }
                    self.installTracking(from: anchor)
                }
                return
            }

            if target !== trackedView {
                tearDownTracking()
                trackedView = target
            }

            let rect = target.bounds
            if let trackingArea, trackingArea.rect == rect, trackingArea.owner as AnyObject? === self {
                return
            }

            if let trackingArea, let trackedView {
                trackedView.removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            target.addTrackingArea(area)
            trackingArea = area

            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    self?.tooltipPanel.hide()
                    return event
                }
            }

            if mouseMovedMonitor == nil {
                mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                    self?.evaluateHover()
                    return event
                }
            }

            if hoverPollTimer == nil {
                hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    self?.evaluateHover()
                }
            }
        }

        private func tearDownTracking() {
            if let trackingArea, let trackedView {
                trackedView.removeTrackingArea(trackingArea)
            }
            trackingArea = nil
            trackedView = nil
            hoverPollTimer?.invalidate()
            hoverPollTimer = nil
        }

        private var currentTitle: String {
            titleProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        @objc func mouseEntered(with event: NSEvent) {
            presentTooltip()
        }

        @objc func mouseExited(with event: NSEvent) {
            scheduleHideTooltip()
        }

        private func evaluateHover() {
            guard let view = trackedView, let window = view.window else {
                if tooltipPanel.isVisible { scheduleHideTooltip() }
                return
            }
            let frameOnScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
            let mouse = NSEvent.mouseLocation
            let paddedFrame = frameOnScreen.insetBy(dx: -2, dy: -2)
            if paddedFrame.contains(mouse) {
                presentTooltip()
            } else if tooltipPanel.isVisible {
                scheduleHideTooltip()
            }
        }

        private func presentTooltip() {
            hideWorkItem?.cancel()
            guard let view = trackedView else { return }
            let title = currentTitle
            guard !title.isEmpty else { return }
            tooltipPanel.show(text: title, relativeTo: view)
        }

        private func scheduleHideTooltip() {
            hideWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.tooltipPanel.hide()
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func findStatusItemView(startingAt view: NSView) -> NSView? {
            var current: NSView? = view
            var statusBarWindowView: NSView?

            while let node = current {
                if node is NSStatusBarButton { return node }

                if let window = node.window,
                   String(describing: type(of: window)).contains("StatusBar"),
                   node.bounds.width > 0,
                   node.bounds.height > 0 {
                    statusBarWindowView = node
                }

                current = node.superview
            }

            return statusBarWindowView
        }
    }
}

private final class MenuBarHoverAnchorView: NSView {
    weak var coordinator: MenuBarHoverTooltip.Coordinator?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleTrackingRefresh()
    }

    override func layout() {
        super.layout()
        if let superview, frame.size != superview.bounds.size {
            frame = superview.bounds
        }
        scheduleTrackingRefresh()
    }

    func scheduleTrackingRefresh() {
        coordinator?.scheduleTrackingRefresh(from: self)
    }
}

private final class MenuBarTooltipPanel {
    private var panel: NSPanel?
    private var contentView: MenuBarTooltipContentView?
    private(set) var isVisible = false

    func show(text: String, relativeTo anchor: NSView) {
        let panel = ensurePanel()
        guard let contentView else { return }
        contentView.configure(text: text)
        applyContentSize(to: panel, contentView: contentView)
        reposition(panel: panel, relativeTo: anchor)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func updateText(_ text: String) {
        guard let contentView, let panel else { return }
        contentView.configure(text: text)
        applyContentSize(to: panel, contentView: contentView)
    }

    private func applyContentSize(to panel: NSPanel, contentView: MenuBarTooltipContentView) {
        let size = contentView.tooltipSize
        contentView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let content = MenuBarTooltipContentView()
        contentView = content

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = content

        self.panel = panel
        return panel
    }

    private func reposition(panel: NSPanel, relativeTo anchor: NSView) {
        guard let window = anchor.window else { return }
        let anchorFrameInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorFrameOnScreen = window.convertToScreen(anchorFrameInWindow)
        let size = panel.frame.size
        let x = anchorFrameOnScreen.midX - size.width / 2
        let y = anchorFrameOnScreen.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class MenuBarTooltipContentView: NSView {
    private static let padding = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = .white
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        return field
    }()

    private(set) var tooltipSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.96).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        let displayText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        label.stringValue = displayText

        let maxLabelWidth: CGFloat = 256
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font as Any
        ]
        let measured = (displayText as NSString).boundingRect(
            with: NSSize(width: maxLabelWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let labelWidth = min(ceil(measured.width), maxLabelWidth)
        let labelHeight = max(ceil(measured.height), 16)

        tooltipSize = NSSize(
            width: labelWidth + Self.padding.left + Self.padding.right,
            height: labelHeight + Self.padding.top + Self.padding.bottom
        )
        frame.size = tooltipSize
        label.frame = NSRect(
            x: Self.padding.left,
            y: Self.padding.bottom,
            width: labelWidth,
            height: labelHeight
        )
        needsDisplay = true
    }
}
