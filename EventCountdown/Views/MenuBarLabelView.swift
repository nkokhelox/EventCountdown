import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @Environment(AppModel.self) private var appModel
    let event: CalendarEvent?
    let resolution: EventEmojiResolution
    let hasStarted: Bool

    private let labelFont = Font.system(size: 13)

    var body: some View {
        // Read tick so the label re-renders every second, keeping the countdown and the
        // "Now"/"Ongoing" text fresh.
        let _ = appModel.tick
        styledLabel
            .overlay {
                MenuBarNativeTooltip(title: tooltipText)
            }
    }

    private var styledLabel: some View {
        menuBarLabel
            .font(labelFont)
            .monospacedDigit()
            .lineLimit(1)
    }

    // Menu bar hover tooltip, e.g. "eat starts @ 12:00": the event name followed by when
    // it starts (upcoming) or ends (in progress). Same-day events show the time only;
    // other days include a short date so the time isn't ambiguous.
    private var tooltipText: String {
        guard let event else { return "" }
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = hasStarted ? event.endDate : event.startDate
        let formatter = Calendar.current.isDateInToday(date) ? Self.tooltipTimeFormatter : Self.tooltipDateTimeFormatter
        let detail = "\(hasStarted ? "ends" : "starts") @ \(formatter.string(from: date))"
        return title.isEmpty ? detail : "\(title) \(detail)"
    }

    private static let tooltipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()

    private static let tooltipDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return formatter
    }()

    private var menuBarLabel: Text {
        let mark = menuBarMarkText

        guard let event else {
            return mark.map { $0 + Text(verbatim: " —") } ?? Text(verbatim: "—")
        }

        if hasStarted {
            return (mark ?? Text(verbatim: "")) + Text(verbatim: " \(ongoingText(for: event))")
        }

        return (mark ?? Text(verbatim: "")) + Text(verbatim: " \(countdownText(for: event))")
    }

    private var menuBarMarkText: Text? {
        if resolution.usesAppIcon,
           let image = AppIconRenderer.image(pointSize: AppIconLabelImage.Style.menuBar.pointSize) {
            return Text(Image(nsImage: image))
        }
        if let character = resolution.character {
            return Text(character)
        }
        return nil
    }

    private func ongoingText(for event: CalendarEvent) -> String {
        let elapsed = appModel.tick.timeIntervalSince(event.startDate)
        return CountdownFormatter.ongoingLabel(elapsedSinceStart: elapsed)
    }

    private func countdownText(for event: CalendarEvent) -> String {
        let remaining = CountdownFormatter.remaining(until: event.startDate, now: appModel.tick)
        var countdown = CountdownFormatter.menuBarDecimalText(remaining: remaining)
        if countdown.count > 24 {
            countdown = String(countdown.prefix(24))
        }
        return countdown
    }
}


private struct MenuBarNativeTooltip: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TooltipAnchorView {
        let view = TooltipAnchorView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {
        nsView.title = title
        nsView.applyTooltip()
    }
}

private final class TooltipAnchorView: NSView {
    var title: String = ""
    private var attempts = 0

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attempts = 0
        applyTooltip()
    }

    override func layout() {
        super.layout()
        if let superview, frame.size != superview.bounds.size {
            frame = superview.bounds
        }
    }

    func applyTooltip() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let buttons = statusButtons()
        guard !buttons.isEmpty else {
            guard attempts < 40 else { return }
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.applyTooltip()
            }
            return
        }
        for button in buttons {
            button.toolTip = text.isEmpty ? nil : text
        }
    }

    private func statusButtons() -> [NSStatusBarButton] {
        var found: [NSStatusBarButton] = []

        var current: NSView? = self
        while let node = current {
            if let button = node as? NSStatusBarButton { found.append(button); break }
            current = node.superview
        }

        for window in NSApp.windows {
            if let content = window.contentView {
                found.append(contentsOf: allStatusButtons(in: content))
            }
        }

        var seen = Set<ObjectIdentifier>()
        return found.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func allStatusButtons(in view: NSView) -> [NSStatusBarButton] {
        var result: [NSStatusBarButton] = []
        if let button = view as? NSStatusBarButton { result.append(button) }
        for sub in view.subviews {
            result.append(contentsOf: allStatusButtons(in: sub))
        }
        return result
    }
}
