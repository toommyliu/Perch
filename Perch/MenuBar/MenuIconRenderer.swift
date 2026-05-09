import AppKit
import CoreText
import Foundation

extension NSColor {
    static let perchMutedWhite = NSColor(calibratedRed: 221.0 / 255.0, green: 227.0 / 255.0, blue: 231.0 / 255.0, alpha: 1)
}

enum MenuIconRenderer {
    static func dateIcon(day: Int) -> NSImage {
        let size = NSSize(width: 22, height: 19)
        let image = NSImage(size: size, flipped: false) { _ in
            drawDateIcon(day: day)
            return true
        }

        image.isTemplate = true
        return image
    }

    private static func drawDateIcon(day: Int) {
        let primaryColor = NSColor.black
        primaryColor.setStroke()
        primaryColor.setFill()

        let calendarRect = NSRect(x: 3.5, y: 1.5, width: 15.0, height: 14.75)
        let calendarPath = NSBezierPath(roundedRect: calendarRect, xRadius: 3.0, yRadius: 3.0)
        calendarPath.lineWidth = 1.35

        NSGraphicsContext.saveGraphicsState()
        calendarPath.addClip()
        NSBezierPath(rect: NSRect(x: calendarRect.minX, y: 12.9, width: calendarRect.width, height: calendarRect.maxY - 12.9)).fill()
        NSGraphicsContext.restoreGraphicsState()

        calendarPath.stroke()

        let textRect = NSRect(x: 3.5, y: 2.15, width: 15.0, height: 10.9)
        drawDateText(day: day, color: primaryColor, in: textRect)
    }

    private static func drawDateText(day: Int, color: NSColor, in rect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: day < 10 ? 10.2 : 9.2,
            weight: .bold
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let dayString = NSAttributedString(string: String(day), attributes: attributes)
        drawTypographicallyCentered(dayString, in: rect)
    }

    private static func drawTypographicallyCentered(_ attributedString: NSAttributedString, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            attributedString.draw(in: rect)
            return
        }

        let line = CTLineCreateWithAttributedString(attributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        guard width.isFinite,
              ascent.isFinite,
              descent.isFinite,
              width > 0,
              ascent > 0
        else {
            attributedString.draw(in: rect)
            return
        }

        let xOffset = CGFloat(CTLineGetPenOffsetForFlush(line, 0.5, Double(rect.width)))
        let baselineY = rect.midY - ((ascent - descent) / 2)

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.minX + xOffset, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
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
