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

        if pendingFileURLs.isEmpty {
            newWindow(opening: nil)
        } else {
            let urls = pendingFileURLs
            pendingFileURLs.removeAll()
            for url in urls {
                newWindow(opening: url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if NSApp.isRunning {
            newWindow(opening: url)
        } else {
            pendingFileURLs.append(url)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if NSApp.isRunning {
            for url in urls {
                newWindow(opening: url)
            }
        } else {
            pendingFileURLs.append(contentsOf: urls)
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let controller = newWindow(opening: nil)
        controller.openDocument(sender)
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
            controller.openDVI(url: url)
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
        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
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

        NSApp.mainMenu = mainMenu
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        controllers.removeAll { $0.window === window }
    }
}
