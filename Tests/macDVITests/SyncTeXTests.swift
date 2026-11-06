import XCTest
@testable import macDVI

final class SyncTeXTests: XCTestCase {
    var synctexURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples")
            .appendingPathComponent("sample.synctex.gz")
    }

    var sampleDVIURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples")
            .appendingPathComponent("sample.dvi")
    }

    func testSyncTeXParserInitialization() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: synctexURL.path))
        guard let parser = SyncTeXParser(url: synctexURL) else {
            XCTFail("Failed to initialize SyncTeXParser from \(synctexURL.path)")
            return
        }

        // Forward sync line 5 (sample.tex: "macDVI smoke test")
        let forward5 = parser.forwardSync(sourceFile: "sample.tex", line: 5)
        XCTAssertNotNil(forward5)
        XCTAssertEqual(forward5?.page, 1)
        XCTAssertEqual(forward5?.line, 5)

        // Forward sync line 8 (sample.tex: "This line is rendered from a TeX DVI file.")
        let forward8 = parser.forwardSync(sourceFile: "sample.tex", line: 8)
        XCTAssertNotNil(forward8)
        XCTAssertEqual(forward8?.page, 1)
        XCTAssertEqual(forward8?.line, 8)
    }

    func testBackwardSync() {
        guard let parser = SyncTeXParser(url: synctexURL) else {
            XCTFail("Failed to initialize SyncTeXParser")
            return
        }

        guard let forward5 = parser.forwardSync(sourceFile: "sample.tex", line: 5) else {
            XCTFail("Forward sync for line 5 failed")
            return
        }

        // Backward sync near the point of line 5
        let backward5 = parser.backwardSync(page: 1, point: forward5.point)
        XCTAssertNotNil(backward5)
        XCTAssertEqual(backward5?.line, 5)
        XCTAssertTrue(backward5?.file.hasSuffix("sample.tex") ?? false)

        guard let forward8 = parser.forwardSync(sourceFile: "sample.tex", line: 8) else {
            XCTFail("Forward sync for line 8 failed")
            return
        }

        // Backward sync near the point of line 8
        let backward8 = parser.backwardSync(page: 1, point: forward8.point)
        XCTAssertNotNil(backward8)
        XCTAssertEqual(backward8?.line, 8)
        XCTAssertTrue(backward8?.file.hasSuffix("sample.tex") ?? false)
    }

    func testSyncTeXServiceLocateAndCache() {
        let service = SyncTeXService.shared
        let located = service.locateSyncTeXFile(for: sampleDVIURL)
        XCTAssertNotNil(located)
        XCTAssertEqual(located?.lastPathComponent, "sample.synctex.gz")

        let forward = service.forwardSync(documentURL: sampleDVIURL, sourceFile: "sample.tex", line: 5)
        XCTAssertNotNil(forward)
        XCTAssertEqual(forward?.page, 1)
        XCTAssertEqual(forward?.line, 5)

        let backward = service.backwardSync(documentURL: sampleDVIURL, page: 1, point: forward!.point)
        XCTAssertNotNil(backward)
        XCTAssertEqual(backward?.line, 5)
    }

    func testDocumentPaneSyncTeXIntegration() {
        let pane = DocumentPane()
        let expectation = expectation(description: "Document load")

        var backwardResult: SyncTeXResult?
        pane.onSyncTeXBackward = { result in
            backwardResult = result
        }

        pane.load(url: sampleDVIURL) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let err):
                XCTFail("Failed to load sample.dvi: \(err)")
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Forward sync to line 5
        let forwardSuccess = pane.forwardSync(sourceFile: "sample.tex", line: 5)
        XCTAssertTrue(forwardSuccess)

        // Backward sync
        let backward = pane.backwardSync(page: 1, point: CGPoint(x: 72.27, y: 82.27))
        XCTAssertNotNil(backward)
        XCTAssertEqual(backward?.line, 5)
        XCTAssertEqual(backwardResult?.line, 5)
    }

    func testPDFDocumentPaneSyncTeXIntegration() {
        let pdfURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples")
            .appendingPathComponent("sample.pdf")

        let pane = DocumentPane()
        let expectation = expectation(description: "PDF load")

        pane.load(url: pdfURL) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let err):
                XCTFail("Failed to load sample.pdf: \(err)")
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Forward sync to line 8
        let forwardSuccess = pane.forwardSync(sourceFile: "sample.tex", line: 8)
        XCTAssertTrue(forwardSuccess)

        // Backward sync
        let backward = pane.backwardSync(page: 1, point: CGPoint(x: 72.27, y: 106.27))
        XCTAssertNotNil(backward)
        XCTAssertEqual(backward?.line, 8)
    }
}
