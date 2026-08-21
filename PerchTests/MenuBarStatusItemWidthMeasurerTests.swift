import AppKit
import XCTest
@testable import Perch

@MainActor
final class MenuBarStatusItemWidthMeasurerTests: XCTestCase {
    func testWideToShortTransitionMatchesFreshStatusItemMeasurement() throws {
        let transitionedStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let freshStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(transitionedStatusItem)
            NSStatusBar.system.removeStatusItem(freshStatusItem)
        }

        let transitionedButton = try XCTUnwrap(transitionedStatusItem.button)
        let freshButton = try XCTUnwrap(freshStatusItem.button)
        configure(button: transitionedButton)
        configure(button: freshButton)

        transitionedButton.title = " A very wide previous event title that already occupies substantial menu bar space · in 5m"
        transitionedButton.window?.layoutIfNeeded()
        transitionedButton.title = " 5m"
        freshButton.title = " 5m"

        let transitionedMeasurer = try XCTUnwrap(MenuBarStatusItemWidthMeasurer(button: transitionedButton))
        let freshMeasurer = try XCTUnwrap(MenuBarStatusItemWidthMeasurer(button: freshButton))
        let candidate = " Short event · in 5m"

        XCTAssertEqual(
            transitionedMeasurer.width(for: candidate),
            freshMeasurer.width(for: candidate),
            accuracy: 0.5
        )
    }

    private func configure(button: NSStatusBarButton) {
        button.imagePosition = .imageLeading
        button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Reminder")
    }
}
