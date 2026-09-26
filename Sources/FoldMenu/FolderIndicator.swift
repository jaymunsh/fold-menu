import AppKit

/// One fixed-size, closed-folder status glyph with a count, including zero.
/// Its width never changes, so updates cannot rearrange the user's menu bar.
enum FolderIndicator {
    static let size = NSSize(width: 26, height: 20)

    static func count(availableIDs: [String], selectedIDs: Set<String>) -> Int {
        Set(availableIDs).intersection(selectedIDs).count
    }

    static func badge(for count: Int) -> String {
        count > 99 ? "99+" : String(max(0, count))
    }

    static func image(count: Int) -> NSImage {
        let badge = badge(for: count)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            // A shallow tab behind the rounded body, rather than a tall
            // double-line header. Keep the same template color and canvas.
            let tab = NSBezierPath()
            tab.lineWidth = 1.15
            tab.lineCapStyle = .round
            tab.lineJoinStyle = .round
            tab.move(to: NSPoint(x: 2.5, y: 13.25))
            tab.line(to: NSPoint(x: 2.5, y: 15.25))
            tab.curve(to: NSPoint(x: 4.25, y: 17), controlPoint1: NSPoint(x: 2.5, y: 16.25), controlPoint2: NSPoint(x: 3.25, y: 17))
            tab.line(to: NSPoint(x: 8.75, y: 17))
            tab.line(to: NSPoint(x: 10.75, y: 15.25))
            tab.stroke()

            let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 2.5, width: 20, height: 12.75),
                                    xRadius: 2.25, yRadius: 2.25)
            body.lineWidth = 1.15
            body.stroke()

            let text = NSAttributedString(string: badge, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: badge.count > 2 ? 7.5 : 9.5, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: 12.5 - textSize.width / 2, y: 8.875 - textSize.height / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}
