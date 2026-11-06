import XCTest
import PDFKit
@testable import macDVI

final class SearchTests: XCTestCase {
    func testDVISearchEngineBasic() throws {
        let sampleURL = URL(fileURLWithPath: "Examples/sample.dvi")
        let doc = try DVIParser(url: sampleURL).parse()
        let engine = DVISearchEngine()

        // Test single word case-insensitive
        let matchesSmoke = engine.search(document: doc, query: "smoke", caseSensitive: false)
        XCTAssertEqual(matchesSmoke.count, 1)
        XCTAssertEqual(matchesSmoke.first?.text, "smoke")
        XCTAssertEqual(matchesSmoke.first?.pageIndex, 0)
        XCTAssertFalse(matchesSmoke.first?.rects.isEmpty ?? true)

        // Test case-sensitive
        let matchesSmokeUpper = engine.search(document: doc, query: "SMOKE", caseSensitive: true)
        XCTAssertEqual(matchesSmokeUpper.count, 0)

        // Test multiple matches
        let matchesDVI = engine.search(document: doc, query: "DVI", caseSensitive: false)
        XCTAssertEqual(matchesDVI.count, 2)
        XCTAssertEqual(matchesDVI[0].text, "DVI")
        XCTAssertEqual(matchesDVI[1].text, "DVI")

        // Test phrase with space
        let matchesPhrase = engine.search(document: doc, query: "smoke test", caseSensitive: false)
        XCTAssertEqual(matchesPhrase.count, 1)
        XCTAssertEqual(matchesPhrase.first?.text, "smoke test")
        XCTAssertEqual(matchesPhrase.first?.rects.count, 1)

        // Test non-matching query
        let matchesNone = engine.search(document: doc, query: "nonexistent word", caseSensitive: false)
        XCTAssertEqual(matchesNone.count, 0)
    }

    func testEmptyAndWhitespaceQuery() throws {
        let sampleURL = URL(fileURLWithPath: "Examples/sample.dvi")
        let doc = try DVIParser(url: sampleURL).parse()
        let engine = DVISearchEngine()

        XCTAssertTrue(engine.search(document: doc, query: "", caseSensitive: false).isEmpty)
        XCTAssertTrue(engine.search(document: doc, query: "   ", caseSensitive: false).isEmpty)
    }

    func testPDFSearch() throws {
        let sampleURL = URL(fileURLWithPath: "Examples/sample.pdf")
        guard let pdfDoc = PDFDocument(url: sampleURL) else {
            XCTFail("Failed to load sample.pdf")
            return
        }

        let matches = pdfDoc.findString("DVI", withOptions: [.caseInsensitive])
        XCTAssertEqual(matches.count, 2)

        let matchesCaseSensitive = pdfDoc.findString("dvi", withOptions: [.literal])
        XCTAssertEqual(matchesCaseSensitive.count, 0)
    }

    func testDocumentPaneSearchNavigation() throws {
        let pane = DocumentPane()
        let expectation = self.expectation(description: "Document load")

        let sampleURL = URL(fileURLWithPath: "Examples/sample.dvi").absoluteURL
        pane.load(url: sampleURL) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Failed to load document: \(error)")
            }
        }
        waitForExpectations(timeout: 5.0)

        // Test find bar visibility toggle
        XCTAssertFalse(pane.isFindBarVisible)
        pane.showFindBar()
        XCTAssertTrue(pane.isFindBarVisible)

        // Perform search
        pane.performSearch(query: "DVI", caseSensitive: false)
        XCTAssertEqual(pane.totalMatches, 2)
        XCTAssertEqual(pane.currentMatchIndex, 0)

        // Navigate forward
        pane.findNext()
        XCTAssertEqual(pane.currentMatchIndex, 1)

        // Wrap around forward
        pane.findNext()
        XCTAssertEqual(pane.currentMatchIndex, 0)

        // Navigate backward
        pane.findPrevious()
        XCTAssertEqual(pane.currentMatchIndex, 1)

        // Wrap around backward
        pane.findPrevious()
        XCTAssertEqual(pane.currentMatchIndex, 0)

        // Hide find bar clears highlights
        pane.hideFindBar()
        XCTAssertFalse(pane.isFindBarVisible)
        XCTAssertEqual(pane.dviView?.searchMatches.count, 0)
    }
}
