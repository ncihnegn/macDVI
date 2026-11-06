import XCTest
import AppKit
@testable import macDVI

final class FitWidthHeightTests: XCTestCase {
    func testDVIDocumentViewFitWidthAndHeight() throws {
        let sampleURL = URL(fileURLWithPath: "Examples/sample.dvi")
        let doc = try DVIParser(url: sampleURL).parse()

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let dviView = DVIDocumentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        dviView.document = doc
        scrollView.documentView = dviView

        dviView.autoScaleMode = .width
        let zoomWidth = dviView.zoom
        XCTAssertGreaterThan(zoomWidth, 0.1)

        dviView.autoScaleMode = .height
        let zoomHeight = dviView.zoom
        XCTAssertGreaterThan(zoomHeight, 0.1)

        // For a non-square 800x600 viewport and standard page, width scale and height scale differ
        XCTAssertNotEqual(zoomWidth, zoomHeight, accuracy: 0.001)
    }

    func testDocumentPaneFitWidthAndHeight() {
        let sampleURL = URL(fileURLWithPath: "Examples/sample.dvi")
        let pane = DocumentPane()
        let exp = expectation(description: "load document")
        pane.load(url: sampleURL) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        pane.fitWidth()
        XCTAssertEqual(pane.autoScaleMode, .width)
        XCTAssertTrue(pane.autoScales)

        pane.fitHeight()
        XCTAssertEqual(pane.autoScaleMode, .height)
        XCTAssertTrue(pane.autoScales)

        pane.actualSize()
        XCTAssertEqual(pane.autoScaleMode, .none)
        XCTAssertFalse(pane.autoScales)
        XCTAssertEqual(pane.zoomFactor, 1.0, accuracy: 0.001)
    }

    func testToolbarFitWidthAndHeight() {
        let controller = DocumentWindowController()
        guard let toolbar = controller.window?.toolbar else {
            XCTFail("Window should have a toolbar")
            return
        }

        let defaultIDs = controller.toolbarDefaultItemIdentifiers(toolbar)
        XCTAssertTrue(defaultIDs.contains(.fitWidth))
        XCTAssertTrue(defaultIDs.contains(.fitHeight))
        XCTAssertFalse(defaultIDs.contains(.zoomToFit))

        let widthItem = controller.toolbar(toolbar, itemForItemIdentifier: .fitWidth, willBeInsertedIntoToolbar: true)
        XCTAssertNotNil(widthItem)
        XCTAssertEqual(widthItem?.label, "Fit Width")
        XCTAssertEqual(widthItem?.action, #selector(DocumentWindowController.fitWidth(_:)))

        let heightItem = controller.toolbar(toolbar, itemForItemIdentifier: .fitHeight, willBeInsertedIntoToolbar: true)
        XCTAssertNotNil(heightItem)
        XCTAssertEqual(heightItem?.label, "Fit Height")
        XCTAssertEqual(heightItem?.action, #selector(DocumentWindowController.fitHeight(_:)))
    }

    func testViewMenuFitWidthAndHeight() {
        let appDelegate = AppDelegate(initialFileURLs: [])
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        guard let mainMenu = NSApp.mainMenu else {
            XCTFail("Main menu should exist")
            return
        }

        guard let viewItem = mainMenu.items.first(where: { $0.title == "View" || $0.submenu?.title == "View" }),
              let viewMenu = viewItem.submenu else {
            XCTFail("View menu should exist")
            return
        }

        // "Zoom to Fit" should no longer be in the menu
        XCTAssertNil(viewMenu.item(withTitle: "Zoom to Fit"))

        // "Fit Width" should be present with ⌘9
        guard let fitWidthItem = viewMenu.item(withTitle: "Fit Width") else {
            XCTFail("Fit Width item should exist in View menu")
            return
        }
        XCTAssertEqual(fitWidthItem.keyEquivalent, "9")
        XCTAssertEqual(fitWidthItem.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(fitWidthItem.action, #selector(AppDelegate.fitWidth(_:)))

        // "Fit Height" should be present with ⌥⌘9
        guard let fitHeightItem = viewMenu.item(withTitle: "Fit Height") else {
            XCTFail("Fit Height item should exist in View menu")
            return
        }
        XCTAssertEqual(fitHeightItem.keyEquivalent, "9")
        XCTAssertEqual(fitHeightItem.keyEquivalentModifierMask, [.command, .option])
        XCTAssertEqual(fitHeightItem.action, #selector(AppDelegate.fitHeight(_:)))
    }
}
