import XCTest
@testable import macDVI

final class FullScreenTopBarTests: XCTestCase {
    func testWindowCollectionBehaviorAndPresentationOptions() {
        let controller = DocumentWindowController()
        guard let window = controller.window else {
            XCTFail("DocumentWindowController should have a window")
            return
        }

        // 1. Verify window supports entering native macOS full screen
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary),
                      "Window should have .fullScreenPrimary collection behavior")

        // 2. Verify DocumentWindowController delegate presentation options auto-hide top bar
        let dcOpts = controller.window(window, willUseFullScreenPresentationOptions: [])
        XCTAssertTrue(dcOpts.contains(.autoHideToolbar),
                      "DocumentWindowController should request .autoHideToolbar in full screen")
        XCTAssertTrue(dcOpts.contains(.autoHideMenuBar),
                      "DocumentWindowController should request .autoHideMenuBar in full screen")
        XCTAssertTrue(dcOpts.contains(.fullScreen),
                      "DocumentWindowController should include .fullScreen")

        // 3. Verify AppDelegate delegate presentation options also auto-hide top bar
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        let appOpts = delegate.window(window, willUseFullScreenPresentationOptions: [])
        XCTAssertTrue(appOpts.contains(.autoHideToolbar),
                      "AppDelegate should request .autoHideToolbar in full screen")
        XCTAssertTrue(appOpts.contains(.autoHideMenuBar),
                      "AppDelegate should request .autoHideMenuBar in full screen")
        XCTAssertTrue(appOpts.contains(.fullScreen),
                      "AppDelegate should include .fullScreen")

        // 4. Verify View menu contains Enter Full Screen with shortcut Control-Command-F
        let viewMenuItem = app.mainMenu?.item(withTitle: "View")
        XCTAssertNotNil(viewMenuItem)
        let fullScreenItem = viewMenuItem?.submenu?.items.first { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        XCTAssertNotNil(fullScreenItem, "View menu should contain toggleFullScreen item")
        XCTAssertEqual(fullScreenItem?.keyEquivalent, "f")
        XCTAssertEqual(fullScreenItem?.keyEquivalentModifierMask, [.command, .control])

        // Clean up windows
        for win in app.windows {
            win.close()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}
