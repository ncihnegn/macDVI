import XCTest
@testable import macDVI

final class SettingsMenuTests: XCTestCase {
    func testSettingsMenuSetupAndItems() {
        let app = NSApplication.shared
        let delegate = AppDelegate(initialFileURLs: [])
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        // 1. Verify "Settings" item in mainMenu (and "Preferences" alias)
        let settingsMenuItem = app.mainMenu?.item(withTitle: "Settings")
        XCTAssertNotNil(settingsMenuItem, "Main menu should contain 'Settings'")
        let preferencesMenuItem = app.mainMenu?.item(withTitle: "Preferences")
        XCTAssertNotNil(preferencesMenuItem, "Main menu should alias 'Preferences' to 'Settings'")

        guard let settingsMenu = settingsMenuItem?.submenu else {
            XCTFail("Settings menu item should have a submenu")
            return
        }

        // 2. Verify Settings... item with key equivalent ','
        let openSettings = settingsMenu.items.first { $0.title == "Settings…" }
        XCTAssertNotNil(openSettings, "Settings menu should contain 'Settings…'")
        XCTAssertEqual(openSettings?.keyEquivalent, ",")

        // 3. Verify App Menu contains Settings... item with key equivalent ','
        let appMenu = app.mainMenu?.items.first?.submenu
        let appSettingsItem = appMenu?.items.first { $0.title == "Settings…" }
        XCTAssertNotNil(appSettingsItem, "App menu should contain 'Settings…'")
        XCTAssertEqual(appSettingsItem?.keyEquivalent, ",")

        // 4. Verify Settings menu items
        let titles = settingsMenu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Default Page View"))
        XCTAssertTrue(titles.contains("Auto-Scale to Window Width"))
        XCTAssertTrue(titles.contains("Remember Last Viewed Page"))
        XCTAssertTrue(titles.contains("TeX Editor"))
        XCTAssertTrue(titles.contains("SyncTeX Highlight Color"))
        XCTAssertTrue(titles.contains("SyncTeX Highlight Duration"))
        XCTAssertTrue(titles.contains("Clear Reading History…"))

        // Clean up windows
        for window in app.windows {
            window.close()
        }
    }

    func testAppSettingsPersistence() {
        let settings = AppSettings.shared

        // Test two-page view setting
        let originalTwoPage = settings.isTwoPageViewEnabled
        settings.isTwoPageViewEnabled = !originalTwoPage
        XCTAssertEqual(settings.isTwoPageViewEnabled, !originalTwoPage)
        settings.isTwoPageViewEnabled = originalTwoPage

        // Test auto scales setting
        let originalAutoScales = settings.isAutoScalesEnabled
        settings.isAutoScalesEnabled = !originalAutoScales
        XCTAssertEqual(settings.isAutoScalesEnabled, !originalAutoScales)
        settings.isAutoScalesEnabled = originalAutoScales

        // Test remember page setting
        let originalRemember = settings.isRememberPageEnabled
        settings.isRememberPageEnabled = !originalRemember
        XCTAssertEqual(settings.isRememberPageEnabled, !originalRemember)
        settings.isRememberPageEnabled = originalRemember

        // Test editor choice
        let originalEditor = settings.selectedEditor
        settings.selectedEditor = .cursor
        XCTAssertEqual(settings.selectedEditor, .cursor)
        settings.selectedEditor = originalEditor

        // Test highlight color
        let originalColor = settings.highlightColor
        settings.highlightColor = .orange
        XCTAssertEqual(settings.highlightColor, .orange)
        settings.highlightColor = originalColor

        // Test highlight duration
        let originalDuration = settings.highlightDuration
        settings.highlightDuration = 5.0
        XCTAssertEqual(settings.highlightDuration, 5.0)
        settings.highlightDuration = originalDuration
    }

    func testSettingsWindowController() {
        let controller = SettingsWindowController.shared
        XCTAssertNotNil(controller.window)
        XCTAssertEqual(controller.window?.title, "Settings")

        // Trigger showWindow and verify window is displayed
        controller.showWindow(nil)
        XCTAssertTrue(controller.window?.isVisible ?? false)

        controller.close()
    }
}
