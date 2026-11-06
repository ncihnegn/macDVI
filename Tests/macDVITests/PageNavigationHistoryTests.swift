import XCTest
import PDFKit
@testable import macDVI

final class PageNavigationHistoryTests: XCTestCase {
    func testHistoryStackOperations() {
        let history = PageNavigationHistory()

        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertNil(history.currentPage)

        // Record page 1
        history.record(pageNumber: 1)
        XCTAssertEqual(history.currentPage, 1)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        // Duplicate record of page 1 should be ignored
        history.record(pageNumber: 1)
        XCTAssertEqual(history.entries.count, 1)

        // Record page 5
        history.record(pageNumber: 5)
        XCTAssertEqual(history.currentPage, 5)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        // Record page 12
        history.record(pageNumber: 12)
        XCTAssertEqual(history.currentPage, 12)
        XCTAssertEqual(history.entries, [1, 5, 12])

        // Go back to 5
        let back1 = history.goBack()
        XCTAssertEqual(back1, 5)
        XCTAssertEqual(history.currentPage, 5)
        XCTAssertTrue(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        // Go back to 1
        let back2 = history.goBack()
        XCTAssertEqual(back2, 1)
        XCTAssertEqual(history.currentPage, 1)
        XCTAssertFalse(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        // Cannot go back further
        XCTAssertNil(history.goBack())

        // Go forward to 5
        let fwd1 = history.goForward()
        XCTAssertEqual(fwd1, 5)
        XCTAssertEqual(history.currentPage, 5)

        // Now branch off by jumping to page 20
        history.record(pageNumber: 20)
        XCTAssertEqual(history.entries, [1, 5, 20])
        XCTAssertEqual(history.currentPage, 20)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward) // Forward history (12) was truncated
    }

    func testDocumentPaneHistoryNavigation() throws {
        // Create a 3-page test PDF
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            XCTFail("Failed to create CGDataConsumer")
            return
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            XCTFail("Failed to create CGContext")
            return
        }
        for _ in 1...3 {
            context.beginPage(mediaBox: &mediaBox)
            context.endPage()
        }
        context.closePDF()

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macDVI_test_multipage_\(UUID().uuidString).pdf")
        try (pdfData as Data).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let pane = DocumentPane()
        let expectation = self.expectation(description: "Document load")

        pane.load(url: tempURL) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Failed to load document: \(error)")
            }
        }
        waitForExpectations(timeout: 5.0)

        // Wait for main queue initialization
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Initially at page 1
        XCTAssertEqual(pane.currentPageNumber, 1)
        XCTAssertFalse(pane.canGoPreviousPage)
        XCTAssertFalse(pane.canGoNextPage)

        // Explicitly jump to page 3
        pane.jumpToPage(3)
        XCTAssertEqual(pane.currentPageNumber, 3)
        XCTAssertTrue(pane.canGoPreviousPage)
        XCTAssertFalse(pane.canGoNextPage)

        // Go back to previous page in history
        pane.previousPage()
        XCTAssertEqual(pane.currentPageNumber, 1)
        XCTAssertFalse(pane.canGoPreviousPage)
        XCTAssertTrue(pane.canGoNextPage)

        // Go forward to next page in history
        pane.nextPage()
        XCTAssertEqual(pane.currentPageNumber, 3)
        XCTAssertTrue(pane.canGoPreviousPage)
        XCTAssertFalse(pane.canGoNextPage)
    }
}
