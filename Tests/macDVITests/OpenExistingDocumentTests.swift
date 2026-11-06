import XCTest
@testable import macDVI

final class OpenExistingDocumentTests: XCTestCase {
    var sampleDVIURL: URL {
        URL(fileURLWithPath: "Examples/sample.dvi").absoluteURL
    }

    var samplePDFURL: URL {
        URL(fileURLWithPath: "Examples/sample.pdf").absoluteURL
    }

    func testOpeningAlreadyOpenFileDoesNotOpenAnotherWindow() {
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Initial empty window created on launch
        let initialWindows = app.windows.filter { $0.isVisible }
        XCTAssertFalse(initialWindows.isEmpty)

        // 1. Open sample.dvi for the first time
        delegate.openDocument(at: sampleDVIURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        guard let firstController = delegate.controller(for: sampleDVIURL) else {
            XCTFail("Controller for sample.dvi should exist")
            return
        }
        let firstWindow = firstController.window
        XCTAssertNotNil(firstWindow)

        let windowCountAfterFirstOpen = app.windows.filter { $0.isVisible }.count

        // 2. Open the exact same file again via openDocument(at:)
        delegate.openDocument(at: sampleDVIURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        let windowCountAfterDuplicateOpen = app.windows.filter { $0.isVisible }.count
        XCTAssertEqual(windowCountAfterDuplicateOpen, windowCountAfterFirstOpen,
                       "Opening an already open file must not create another window")

        // Check that firstWindow is still the active/focused window
        XCTAssertTrue(firstWindow?.isKeyWindow == true || firstWindow?.isVisible == true)

        // 3. Open via relative/alternative path
        let relativeURL = URL(fileURLWithPath: "./Examples/sample.dvi")
        delegate.openDocument(at: relativeURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        let windowCountAfterRelativeOpen = app.windows.filter { $0.isVisible }.count
        XCTAssertEqual(windowCountAfterRelativeOpen, windowCountAfterFirstOpen,
                       "Opening the same file via relative path must resolve to existing window")

        // 4. Open a different file (sample.pdf)
        delegate.openDocument(at: samplePDFURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        let windowCountWithTwoDocs = app.windows.filter { $0.isVisible }.count
        XCTAssertEqual(windowCountWithTwoDocs, windowCountAfterFirstOpen + 1,
                       "Opening a different file should open another window")

        // 5. Re-open sample.dvi: should jump back to first window without adding third window
        delegate.openDocument(at: sampleDVIURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        let windowCountAfterJumpBack = app.windows.filter { $0.isVisible }.count
        XCTAssertEqual(windowCountAfterJumpBack, windowCountWithTwoDocs,
                       "Re-opening first document should jump to its window without opening a new one")

        // Clean up windows
        for window in app.windows {
            window.close()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    func testSideBySideDocumentDeduplication() {
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Open primary document
        delegate.openDocument(at: sampleDVIURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        guard let controller = delegate.controller(for: sampleDVIURL) else {
            XCTFail("Should find controller for sample.dvi")
            return
        }

        // Open secondary document side-by-side
        controller.openSideBySide(url: samplePDFURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        XCTAssertTrue(controller.containsDocument(url: sampleDVIURL))
        XCTAssertTrue(controller.containsDocument(url: samplePDFURL))

        let windowCountBefore = app.windows.filter { $0.isVisible }.count

        // Open samplePDFURL via delegate: should jump to this window rather than opening a new window
        delegate.openDocument(at: samplePDFURL)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        let windowCountAfter = app.windows.filter { $0.isVisible }.count
        XCTAssertEqual(windowCountAfter, windowCountBefore,
                       "Opening a file that is already in secondary side-by-side pane must not open a new window")

        // Focus should be on secondary pane
        XCTAssertEqual(controller.focusedPane, controller.secondaryPane)

        // Clean up windows
        for window in app.windows {
            window.close()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}
