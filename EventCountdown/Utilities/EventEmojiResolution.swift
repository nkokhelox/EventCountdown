import AppKit
import Foundation
import SwiftUI

struct EventEmojiResolution: Equatable, Sendable {
    let character: String?
    let usesAppIcon: Bool

    static let appIcon = EventEmojiResolution(character: nil, usesAppIcon: true)

    init(character: String) {
        self.character = character
        self.usesAppIcon = false
    }

    private init(character: String?, usesAppIcon: Bool) {
        self.character = character
        self.usesAppIcon = usesAppIcon
    }
}

enum AppIconRenderer {
    static func image(pointSize: CGFloat, screen: NSScreen? = NSScreen.main) -> NSImage? {
        guard let source = NSApplication.shared.applicationIconImage else { return nil }

        let scale = screen?.backingScaleFactor ?? 2.0
        let pixelDimension = pointSize * scale

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelDimension.rounded()),
            pixelsHigh: Int(pixelDimension.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let inset = pointSize * 0.06
        let drawRect = NSRect(
            x: inset,
            y: inset,
            width: pointSize - (2 * inset),
            height: pointSize - (2 * inset)
        )
        let corner = pointSize * 0.22
        NSBezierPath(roundedRect: drawRect, xRadius: corner, yRadius: corner).addClip()

        if let best = source.bestRepresentation(for: drawRect, context: context, hints: nil) {
            best.draw(in: drawRect)
        } else {
            source.draw(in: drawRect)
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        return image
    }
}

struct AppIconLabelImage: View {
    enum Style {
        case menuBar
        case inline

        var pointSize: CGFloat {
            switch self {
            case .menuBar: return 30
            case .inline: return 13
            }
        }

        var baselineOffset: CGFloat {
            switch self {
            case .menuBar: return 0.12
            case .inline: return 0
            }
        }
    }

    var style: Style = .inline

    var body: some View {
        if let image = AppIconRenderer.image(pointSize: style.pointSize) {
            Image(nsImage: image)
                .frame(width: style.pointSize, height: style.pointSize)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    guard style.baselineOffset > 0 else { return dimensions[.bottom] }
                    return dimensions[.bottom] - (style.pointSize * style.baselineOffset)
                }
        }
    }
}
