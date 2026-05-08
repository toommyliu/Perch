import AppKit
import Foundation

extension NSColor {
    static let perchMutedWhite = NSColor(calibratedRed: 221.0 / 255.0, green: 227.0 / 255.0, blue: 231.0 / 255.0, alpha: 1)
}

enum MenuIconRenderer {
    static func dateIcon(day: Int) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        let primaryColor = NSColor.black
        primaryColor.setStroke()
        primaryColor.setFill()

        let calendarRect = NSRect(x: 3.5, y: 2.5, width: 15.0, height: 13.0)
        let calendarPath = NSBezierPath(roundedRect: calendarRect, xRadius: 2.5, yRadius: 2.5)
        calendarPath.lineWidth = 1.2
        calendarPath.stroke()

        let headerPath = NSBezierPath()
        headerPath.lineWidth = 1.1
        headerPath.lineCapStyle = .round
        headerPath.move(to: NSPoint(x: 5.5, y: 12.5))
        headerPath.line(to: NSPoint(x: 16.5, y: 12.5))
        headerPath.stroke()

        NSBezierPath(ovalIn: NSRect(x: 7.0, y: 14.5, width: 1.5, height: 1.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 13.5, y: 14.5, width: 1.5, height: 1.5)).fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: day < 10 ? 9.8 : 9.0, weight: .semibold),
            .foregroundColor: primaryColor,
            .paragraphStyle: paragraphStyle
        ]

        String(day).draw(
            in: NSRect(x: 3.5, y: 3.5, width: 15.0, height: 9.5),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func colorBar(color: NSColor, size: NSSize = NSSize(width: 5, height: 16)) -> NSImage {
        let image = NSImage(size: size)

        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()

        image.isTemplate = false
        return image
    }

    static func zoomIcon(size: NSSize = NSSize(width: 16, height: 16)) -> NSImage {
        let image = NSImage(size: size)
        let rect = NSRect(origin: .zero, size: size)

        image.lockFocus()

        NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            xRadius: 3,
            yRadius: 3
        ).fill()

        NSColor.white.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 4, y: 5.5, width: 6.5, height: 5),
            xRadius: 1,
            yRadius: 1
        ).fill()

        let lens = NSBezierPath()
        lens.move(to: NSPoint(x: 10.5, y: 7))
        lens.line(to: NSPoint(x: 13, y: 5.75))
        lens.line(to: NSPoint(x: 13, y: 10.25))
        lens.line(to: NSPoint(x: 10.5, y: 9))
        lens.close()
        lens.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
