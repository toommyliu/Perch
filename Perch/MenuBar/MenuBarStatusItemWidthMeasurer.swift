import AppKit

@MainActor
struct MenuBarStatusItemWidthMeasurer {
    private let measurementCell: NSButtonCell
    private let statusItemChromeWidth: CGFloat

    /// Captures status-item padding from the button's current, fully laid-out content.
    init?(button: NSStatusBarButton) {
        if let window = button.window {
            window.layoutIfNeeded()
        } else {
            button.layoutSubtreeIfNeeded()
        }

        guard let measurementCell = button.cell?.copy() as? NSButtonCell else { return nil }
        measurementCell.title = button.title
        self.measurementCell = measurementCell
        statusItemChromeWidth = max(0, button.frame.width - measurementCell.cellSize.width)
    }

    /// Returns the complete status-item width for a candidate title.
    func width(for title: String) -> CGFloat {
        measurementCell.title = title
        return measurementCell.cellSize.width + statusItemChromeWidth
    }
}
