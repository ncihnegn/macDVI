import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [DocumentWindowController] = []
    private var pendingFileURLs: [URL]
    private var pendingSyncTeXForward: (sourceFile: String, line: Int, column: Int?, docURL: URL?)?

    init(initialFileURLs: [URL], initialSyncTeXForward: (sourceFile: String, line: Int, column: Int?, docURL: URL?)? = nil) {
        self.pendingFileURLs = initialFileURLs
        self.pendingSyncTeXForward = initialSyncTeXForward
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        buildMenu()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedSyncTeXForward(_:)),
            name: Notification.Name("com.macDVI.synctexForward"),
            object: nil
        )

        let urls = pendingFileURLs
        pendingFileURLs.removeAll()
        if urls.count == 2 {
            let controller = newWindow(opening: urls[0])
            controller.openSideBySide(url: urls[1])
        } else {
            for url in urls {
                newWindow(opening: url)
            }
        }
        if controllers.isEmpty {
            newWindow(opening: nil)
        }

        if let pending = pendingSyncTeXForward {
            pendingSyncTeXForward = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.forwardSync(
                    docURL: pending.docURL,
                    sourceFile: pending.sourceFile,
                    line: pending.line,
                    column: pending.column
                )
            }
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

    @objc func newWindow(_ sender: Any?) {
        newWindow(opening: nil)
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

    @objc func openSideBySide(_ sender: Any?) {
        keyController?.openSideBySide(sender)
    }

    @objc func closeSideBySide(_ sender: Any?) {
        keyController?.closeSideBySide(sender)
    }

    @objc func toggleSyncLock(_ sender: Any?) {
        keyController?.toggleSyncLock(sender)
    }

    @objc func resetAlignmentOffset(_ sender: Any?) {
        keyController?.resetAlignmentOffset(sender)
    }

    @objc func toggleSyncScrolling(_ sender: Any?) {
        keyController?.toggleSyncScrolling(sender)
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

    @objc func zoomToFit(_ sender: Any?) {
        keyController?.zoomToFit(sender)
    }

    @objc func toggleTwoPageView(_ sender: Any?) {
        keyController?.toggleTwoPageView(sender)
    }

    @objc func setSinglePageMode(_ sender: Any?) {
        keyController?.setSinglePageMode(sender)
    }

    @objc func setTwoPagesMode(_ sender: Any?) {
        keyController?.setTwoPagesMode(sender)
    }

    @objc func pageDown(_ sender: Any?) {
        keyController?.pageDown(sender)
    }

    @objc func pageUp(_ sender: Any?) {
        keyController?.pageUp(sender)
    }

    var canGoNextPage: Bool {
        keyController?.canGoNextPage ?? false
    }

    var canGoPreviousPage: Bool {
        keyController?.canGoPreviousPage ?? false
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

    @objc func performFind(_ sender: Any?) {
        keyController?.performFind(sender)
    }

    @objc func findNext(_ sender: Any?) {
        keyController?.findNext(sender)
    }

    @objc func findPrevious(_ sender: Any?) {
        keyController?.findPrevious(sender)
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        keyController?.useSelectionForFind(sender)
    }

    @objc func jumpToTeXSource(_ sender: Any?) {
        keyController?.jumpToTeXSource(sender)
    }

    @objc private func handleDistributedSyncTeXForward(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let file = userInfo["file"] as? String,
              let lineStr = userInfo["line"] as? String,
              let line = Int(lineStr) else { return }
        let col = (userInfo["col"] as? String).flatMap { Int($0) }
        let docPath = userInfo["doc"] as? String
        let docURL = docPath.flatMap { URL(fileURLWithPath: $0) }

        NSApp.activate(ignoringOtherApps: true)
        forwardSync(docURL: docURL, sourceFile: file, line: line, column: col)
    }

    @discardableResult
    func forwardSync(docURL: URL?, sourceFile: String, line: Int, column: Int? = nil) -> Bool {
        if let docURL {
            let standardDoc = docURL.standardizedFileURL
            if let controller = controllers.first(where: {
                $0.currentURL?.standardizedFileURL == standardDoc ||
                $0.currentURL?.lastPathComponent == docURL.lastPathComponent
            }) {
                controller.window?.makeKeyAndOrderFront(nil)
                return controller.forwardSync(sourceFile: sourceFile, line: line, column: column)
            } else {
                let controller = newWindow(opening: docURL)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    controller.forwardSync(sourceFile: sourceFile, line: line, column: column)
                }
                return true
            }
        } else if let controller = keyController {
            return controller.forwardSync(sourceFile: sourceFile, line: line, column: column)
        }
        return false
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
        let mainMenu = MainMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About macDVI", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit macDVI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        newWindowItem.target = self
        fileMenu.addItem(newWindowItem)

        let openItem = NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let openSideBySideItem = NSMenuItem(title: "Open Side by Side…", action: #selector(openSideBySide(_:)), keyEquivalent: "o")
        openSideBySideItem.keyEquivalentModifierMask = [.command, .option]
        openSideBySideItem.target = self
        fileMenu.addItem(openSideBySideItem)

        let closeSideBySideItem = NSMenuItem(title: "Close Side by Side", action: #selector(closeSideBySide(_:)), keyEquivalent: "w")
        closeSideBySideItem.keyEquivalentModifierMask = [.command, .shift]
        closeSideBySideItem.target = self
        fileMenu.addItem(closeSideBySideItem)

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

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        editMenu.addItem(.separator())
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findSubmenu = NSMenu(title: "Find")

        let findMenuItem = NSMenuItem(title: "Find…", action: #selector(performFind(_:)), keyEquivalent: "f")
        findMenuItem.target = self
        findSubmenu.addItem(findMenuItem)

        let findNextMenuItem = NSMenuItem(title: "Find Next", action: #selector(findNext(_:)), keyEquivalent: "g")
        findNextMenuItem.target = self
        findSubmenu.addItem(findNextMenuItem)

        let findPrevMenuItem = NSMenuItem(title: "Find Previous", action: #selector(findPrevious(_:)), keyEquivalent: "g")
        findPrevMenuItem.keyEquivalentModifierMask = [.command, .shift]
        findPrevMenuItem.target = self
        findSubmenu.addItem(findPrevMenuItem)

        let useSelectionMenuItem = NSMenuItem(title: "Use Selection for Find", action: #selector(useSelectionForFind(_:)), keyEquivalent: "e")
        useSelectionMenuItem.target = self
        findSubmenu.addItem(useSelectionMenuItem)

        findItem.submenu = findSubmenu
        editMenu.addItem(findItem)

        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        zoomInItem.target = self
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        zoomOutItem.target = self
        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(actualSize(_:)), keyEquivalent: "0")
        actualSizeItem.target = self
        let zoomToFitItem = NSMenuItem(title: "Zoom to Fit", action: #selector(zoomToFit(_:)), keyEquivalent: "9")
        zoomToFitItem.target = self
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(actualSizeItem)
        viewMenu.addItem(zoomToFitItem)

        viewMenu.addItem(.separator())
        let singlePageItem = NSMenuItem(title: "Single Page", action: #selector(setSinglePageMode(_:)), keyEquivalent: "1")
        singlePageItem.keyEquivalentModifierMask = [.command, .option]
        singlePageItem.target = self
        let twoPagesItem = NSMenuItem(title: "Two Pages", action: #selector(setTwoPagesMode(_:)), keyEquivalent: "2")
        twoPagesItem.keyEquivalentModifierMask = [.command, .option]
        twoPagesItem.target = self
        viewMenu.addItem(singlePageItem)
        viewMenu.addItem(twoPagesItem)

        viewMenu.addItem(.separator())
        let syncLockItem = NSMenuItem(title: "Lock Sync", action: #selector(toggleSyncLock(_:)), keyEquivalent: "s")
        syncLockItem.keyEquivalentModifierMask = [.command, .option]
        syncLockItem.target = self
        let resetAlignmentItem = NSMenuItem(title: "Reset Alignment", action: #selector(resetAlignmentOffset(_:)), keyEquivalent: "")
        resetAlignmentItem.target = self
        viewMenu.addItem(syncLockItem)
        viewMenu.addItem(resetAlignmentItem)

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
        let jumpToSourceItem = NSMenuItem(
            title: "Jump to TeX Source",
            action: #selector(jumpToTeXSource(_:)),
            keyEquivalent: "j"
        )
        jumpToSourceItem.keyEquivalentModifierMask = [.command, .shift]
        jumpToSourceItem.target = self
        goMenu.addItem(jumpToSourceItem)
        goMenu.addItem(.separator())
        goMenu.addItem(pageDownItem)
        goMenu.addItem(pageUpItem)
        goMenu.addItem(.separator())
        goMenu.addItem(firstPageItem)
        goMenu.addItem(lastPageItem)

        goItem.submenu = goMenu
        mainMenu.addItem(goItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.title = "Window"

        let minimizeItem = NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        let zoomItem = NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        let bringAllItem = NSMenuItem(
            title: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        windowMenu.addItem(minimizeItem)
        windowMenu.addItem(zoomItem)
        windowMenu.addItem(.separator())
        windowMenu.addItem(bringAllItem)
        windowMenu.addItem(.separator())

        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.windowsMenu = windowMenu
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

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setSinglePageMode(_:)) {
            let isTwo = keyController?.isTwoPageView ?? false
            menuItem.state = isTwo ? .off : .on
            return keyController?.currentURL != nil
        }
        if menuItem.action == #selector(setTwoPagesMode(_:)) {
            let isTwo = keyController?.isTwoPageView ?? false
            menuItem.state = isTwo ? .on : .off
            return keyController?.currentURL != nil
        }
        if menuItem.action == #selector(toggleTwoPageView(_:)) {
            let isTwo = keyController?.isTwoPageView ?? false
            menuItem.state = isTwo ? .on : .off
            return keyController?.currentURL != nil
        }
        if menuItem.action == #selector(openSideBySide(_:)) {
            return keyController?.currentURL != nil
        }
        if menuItem.action == #selector(closeSideBySide(_:)) {
            return keyController?.secondaryPane != nil
        }
        if menuItem.action == #selector(toggleSyncLock(_:)) || menuItem.action == #selector(toggleSyncScrolling(_:)) {
            let isLocked = keyController?.isSyncLocked ?? false
            menuItem.state = isLocked ? .on : .off
            return keyController?.secondaryPane != nil
        }
        if menuItem.action == #selector(resetAlignmentOffset(_:)) {
            return keyController?.secondaryPane != nil
        }
        if menuItem.action == #selector(nextPage(_:)) {
            return canGoNextPage
        }
        if menuItem.action == #selector(previousPage(_:)) {
            return canGoPreviousPage
        }
        return true
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

private final class MainMenu: NSMenu {
    override func item(withTitle title: String) -> NSMenuItem? {
        if let item = super.item(withTitle: title) {
            return item
        }
        if title == "Windows" {
            return super.item(withTitle: "Window")
        }
        if title == "Window" {
            return super.item(withTitle: "Windows")
        }
        return nil
    }
}
