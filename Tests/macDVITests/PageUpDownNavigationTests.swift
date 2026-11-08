import XCTest
import AppKit
import PDFKit
@testable import macDVI

final class PageUpDownNavigationTests: XCTestCase {
    func testGoMenuPageUpDownFirstLastKeyEquivalents() throws {
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        guard let goMenuItem = app.mainMenu?.item(withTitle: "Go"),
              let goMenu = goMenuItem.submenu else {
            XCTFail("Main menu should contain 'Go' menu with submenu")
            return
        }

        // Verify Page Down
        guard let pageDownItem = goMenu.items.first(where: { $0.title == "Page Down" }) else {
            XCTFail("Go menu should contain 'Page Down'")
            return
        }
        XCTAssertEqual(pageDownItem.keyEquivalent, String(UnicodeScalar(NSDownArrowFunctionKey)!))
        XCTAssertEqual(pageDownItem.keyEquivalentModifierMask, [.option], "Page Down should have Option modifier mask")
        XCTAssertEqual(pageDownItem.action, #selector(DocumentWindowController.pageDown(_:)))

        // Verify Page Up
        guard let pageUpItem = goMenu.items.first(where: { $0.title == "Page Up" }) else {
            XCTFail("Go menu should contain 'Page Up'")
            return
        }
        XCTAssertEqual(pageUpItem.keyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(pageUpItem.keyEquivalentModifierMask, [.option], "Page Up should have Option modifier mask")
        XCTAssertEqual(pageUpItem.action, #selector(DocumentWindowController.pageUp(_:)))

        // Verify First Page
        guard let firstPageItem = goMenu.items.first(where: { $0.title == "First Page" }) else {
            XCTFail("Go menu should contain 'First Page'")
            return
        }
        XCTAssertEqual(firstPageItem.keyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(firstPageItem.keyEquivalentModifierMask, [.command], "First Page should have Command modifier mask")
        XCTAssertEqual(firstPageItem.action, #selector(DocumentWindowController.firstPage(_:)))

        // Verify Last Page
        guard let lastPageItem = goMenu.items.first(where: { $0.title == "Last Page" }) else {
            XCTFail("Go menu should contain 'Last Page'")
            return
        }
        XCTAssertEqual(lastPageItem.keyEquivalent, String(UnicodeScalar(NSDownArrowFunctionKey)!))
        XCTAssertEqual(lastPageItem.keyEquivalentModifierMask, [.command], "Last Page should have Command modifier mask")
        XCTAssertEqual(lastPageItem.action, #selector(DocumentWindowController.lastPage(_:)))

        for window in app.windows {
            window.close()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    func testPDFDocumentPanePageUpDownDoesNotCrash() throws {
        let samplePDF = URL(fileURLWithPath: "Examples/sample.pdf").absoluteURL
        guard FileManager.default.fileExists(atPath: samplePDF.path) else {
            throw XCTSkip("Examples/sample.pdf not found")
        }

        let pane = DocumentPane()
        let exp = expectation(description: "load PDF")
        pane.load(url: samplePDF) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        // Calling pageDown and pageUp on DocumentPane displaying a PDF should safely invoke scrollPageDown/scrollPageUp
        pane.pageDown(nil)
        pane.pageUp(nil)
        pane.firstPage(nil)
        pane.lastPage(nil)
    }

    func testDVIDocumentPanePageUpDown() throws {
        let sampleDVI = URL(fileURLWithPath: "Examples/sample.dvi").absoluteURL
        guard FileManager.default.fileExists(atPath: sampleDVI.path) else {
            throw XCTSkip("Examples/sample.dvi not found")
        }

        let pane = DocumentPane()
        let exp = expectation(description: "load DVI")
        pane.load(url: sampleDVI) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)

        pane.pageDown(nil)
        pane.pageUp(nil)
        pane.firstPage(nil)
        pane.lastPage(nil)
    }

    func testDVIDocumentViewKeyNavigationAndScrolling() throws {
        let sampleDVI = URL(fileURLWithPath: "Examples/sample.dvi").absoluteURL
        guard FileManager.default.fileExists(atPath: sampleDVI.path) else {
            throw XCTSkip("Examples/sample.dvi not found")
        }

        let doc = try DVIParser(url: sampleDVI).parse()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let dviView = DVIDocumentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        dviView.document = doc
        scrollView.documentView = dviView

        // Test moveToBeginningOfDocument and moveToEndOfDocument
        dviView.moveToBeginningOfDocument(nil)
        XCTAssertEqual(dviView.currentPageIndex, 0)

        dviView.moveToEndOfDocument(nil)
        // Document should be scrolled towards bottom without crashing
        dviView.moveToBeginningOfDocument(nil)

        // Test Fit Height delegating page down / up to next / previous page
        dviView.autoScaleMode = .height
        let initialPage = dviView.currentPageIndex
        dviView.scrollPageDown()
        if (dviView.document?.pages.count ?? 0) > 1 {
            XCTAssertEqual(dviView.currentPageIndex, initialPage + 1)
            dviView.scrollPageUp()
            XCTAssertEqual(dviView.currentPageIndex, initialPage)
        }
    }
}
