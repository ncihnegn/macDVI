import XCTest
@testable import macDVI

final class WindowMenuTests: XCTestCase {
    func testWindowMenuSetupAndListing() throws {
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // Check mainMenu has Window menu (accessible as "Window" or "Windows")
        let windowMenuItem = app.mainMenu?.item(withTitle: "Window")
        XCTAssertNotNil(windowMenuItem, "Main menu should contain 'Window' menu item")
        let windowsMenuItem = app.mainMenu?.item(withTitle: "Windows")
        XCTAssertNotNil(windowsMenuItem, "Main menu should also find 'Windows' menu item")

        // Check NSApp.windowsMenu is configured
        let windowsMenu = app.windowsMenu
        XCTAssertNotNil(windowsMenu, "NSApp.windowsMenu should be configured")
        guard let menu = windowsMenu else { return }

        // Check standard Window menu items exist
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Minimize"), "Window menu should contain Minimize")
        XCTAssertTrue(titles.contains("Zoom"), "Window menu should contain Zoom")
        XCTAssertTrue(titles.contains("Bring All to Front"), "Window menu should contain Bring All to Front")

        // Check that open windows are listed in the menu
        let sampleDVI = URL(fileURLWithPath: "Examples/sample.dvi").absoluteURL
        delegate.openDocument(at: sampleDVI)

        let samplePDF = URL(fileURLWithPath: "Examples/sample.pdf").absoluteURL
        delegate.openDocument(at: samplePDF)

        // Give RunLoop a quick pump to process window notifications
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        let updatedTitles = menu.items.map { $0.title }
        XCTAssertTrue(updatedTitles.contains("sample.dvi") || updatedTitles.contains("sample.pdf"),
                      "Window menu should list opened document windows: \(updatedTitles)")

        // Clean up windows
        for window in app.windows {
            window.close()
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
}
