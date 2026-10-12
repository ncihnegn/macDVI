import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [DocumentWindowController] = []
    private var pendingFileURLs: [URL]

    init(initialFileURLs: [URL]) {
        self.pendingFileURLs = initialFileURLs
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()

        let urls = pendingFileURLs
        pendingFileURLs.removeAll()
        for url in urls {
            newWindow(opening: url)
        }
        if controllers.isEmpty {
            newWindow(opening: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers {
            controller.saveCurrentPage()
        }
    }

    func openDocument(at url: URL) {
        if let emptyController = controllers.first(where: { $0.currentURL == nil }) {
            emptyController.window?.makeKeyAndOrderFront(nil)
            emptyController.openDocument(url: url)
        } else {
            newWindow(opening: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if NSApp.isRunning {
            openDocument(at: url)
        } else {
            pendingFileURLs.append(url)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if NSApp.isRunning {
            for url in urls {
                openDocument(at: url)
            }
        } else {
            pendingFileURLs.append(contentsOf: urls)
        }
    }

    @objc func openRecentDocumentItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openDocument(at: url)
    }

    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    @objc func openDocument(_ sender: Any?) {
        if let emptyController = controllers.first(where: { $0.currentURL == nil }) {
            emptyController.window?.makeKeyAndOrderFront(nil)
            emptyController.openDocument(sender)
        } else {
            let controller = newWindow(opening: nil)
            controller.openDocument(sender)
        }
    }

    @objc func zoomIn(_ sender: Any?) {
        keyController?.zoomIn(sender)
    }

    @objc func zoomOut(_ sender: Any?) {
        keyController?.zoomOut(sender)
    }

    @objc func actualSize(_ sender: Any?) {
        keyController?.actualSize(sender)
    }

    @objc func pageDown(_ sender: Any?) {
        keyController?.pageDown(sender)
    }

    @objc func pageUp(_ sender: Any?) {
        keyController?.pageUp(sender)
    }

    @objc func nextPage(_ sender: Any?) {
        keyController?.nextPage(sender)
    }

    @objc func previousPage(_ sender: Any?) {
        keyController?.previousPage(sender)
    }

    @objc func firstPage(_ sender: Any?) {
        keyController?.firstPage(sender)
    }

    @objc func lastPage(_ sender: Any?) {
        keyController?.lastPage(sender)
    }

    @objc func goToPage(_ sender: Any?) {
        keyController?.goToPage(sender)
    }

    private var keyController: DocumentWindowController? {
        guard let keyWindow = NSApp.keyWindow else {
            return controllers.last
        }
        return controllers.first { $0.window === keyWindow }
    }

    @discardableResult
    private func newWindow(opening url: URL?) -> DocumentWindowController {
        let controller = DocumentWindowController()
        controllers.append(controller)
        controller.window?.delegate = self
        controller.showWindow(nil)
        if let url {
            controller.openDocument(url: url)
        }
        return controller
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About macDVI", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit macDVI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        openRecentMenu.delegate = self
        populateRecentDocumentsMenu(openRecentMenu)
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        zoomInItem.target = self
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        zoomOutItem.target = self
        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(actualSize(_:)), keyEquivalent: "0")
        actualSizeItem.target = self
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(actualSizeItem)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let goItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")

        let nextItem = NSMenuItem(title: "Next Page", action: #selector(nextPage(_:)), keyEquivalent: "]")
        nextItem.target = self
        let prevItem = NSMenuItem(title: "Previous Page", action: #selector(previousPage(_:)), keyEquivalent: "[")
        prevItem.target = self

        let pageDownItem = NSMenuItem(
            title: "Page Down",
            action: #selector(pageDown(_:)),
            keyEquivalent: String(utf16CodeUnits: [unichar(NSPageDownFunctionKey)], count: 1)
        )
        pageDownItem.target = self

        let pageUpItem = NSMenuItem(
            title: "Page Up",
            action: #selector(pageUp(_:)),
            keyEquivalent: String(utf16CodeUnits: [unichar(NSPageUpFunctionKey)], count: 1)
        )
        pageUpItem.target = self

        let firstPageItem = NSMenuItem(
            title: "First Page",
            action: #selector(firstPage(_:)),
            keyEquivalent: String(utf16CodeUnits: [unichar(NSHomeFunctionKey)], count: 1)
        )
        firstPageItem.target = self

        let lastPageItem = NSMenuItem(
            title: "Last Page",
            action: #selector(lastPage(_:)),
            keyEquivalent: String(utf16CodeUnits: [unichar(NSEndFunctionKey)], count: 1)
        )
        lastPageItem.target = self

        let goToPageItem = NSMenuItem(title: "Go to Page…", action: #selector(goToPage(_:)), keyEquivalent: "g")
        goToPageItem.keyEquivalentModifierMask = [.command, .option]
        goToPageItem.target = self

        let goToPageItemJ = NSMenuItem(title: "Go to Page…", action: #selector(goToPage(_:)), keyEquivalent: "j")
        goToPageItemJ.keyEquivalentModifierMask = [.command]
        goToPageItemJ.target = self
        goToPageItemJ.isAlternate = true

        goMenu.addItem(nextItem)
        goMenu.addItem(prevItem)
        goMenu.addItem(.separator())
        goMenu.addItem(goToPageItem)
        goMenu.addItem(goToPageItemJ)
        goMenu.addItem(.separator())
        goMenu.addItem(pageDownItem)
        goMenu.addItem(pageUpItem)
        goMenu.addItem(.separator())
        goMenu.addItem(firstPageItem)
        goMenu.addItem(lastPageItem)

        goItem.submenu = goMenu
        mainMenu.addItem(goItem)

        NSApp.mainMenu = mainMenu
    }

    private func populateRecentDocumentsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        for url in recentURLs {
            let item = NSMenuItem(
                title: url.lastPathComponent,
                action: #selector(openRecentDocumentItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !recentURLs.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = NSMenuItem(
            title: "Clear Menu",
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = !recentURLs.isEmpty
        menu.addItem(clearItem)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Open Recent" {
            populateRecentDocumentsMenu(menu)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let controller = controllers.first(where: { $0.window === window }) {
            controller.saveCurrentPage()
        }
        controllers.removeAll { $0.window === window }
    }
}
