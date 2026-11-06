import AppKit
import UniformTypeIdentifiers
import PDFKit

final class DocumentWindowController: NSWindowController {
    private let contentContainer = NSView()
    private let statusField = NSTextField(labelWithString: "Open a document")

    private let primaryPane = DocumentPane()
    private(set) var secondaryPane: DocumentPane?
    private let splitView = NSSplitView()

    var currentURL: URL? {
        primaryPane.currentURL
    }

    private(set) var isTwoPageView = false
    private weak var pageViewSegmentedControl: NSSegmentedControl?
    private(set) var isSyncLocked = false
    private(set) var alignmentOffset: Double = 0.0
    private var isSyncing = false

    var isSyncScrollingEnabled: Bool {
        isSyncLocked
    }

    var focusedPane: DocumentPane {
        guard let sec = secondaryPane, let window else { return primaryPane }
        if let responder = window.firstResponder as? NSView {
            if responder.isDescendant(of: sec.containerView) {
                return sec
            }
        }
        return primaryPane
    }

    func containsDocument(url: URL) -> Bool {
        if let primaryURL = primaryPane.currentURL, primaryURL.matchesDocumentURL(url) {
            return true
        }
        if let secondaryURL = secondaryPane?.currentURL, secondaryURL.matchesDocumentURL(url) {
            return true
        }
        return false
    }

    func focusDocument(url: URL) {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let secondary = secondaryPane,
           let secondaryURL = secondary.currentURL,
           secondaryURL.matchesDocumentURL(url) {
            updatePaneFocus(activePane: secondary)
            secondary.makeFirstResponder()
        } else {
            updatePaneFocus(activePane: primaryPane)
            primaryPane.makeFirstResponder()
        }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "macDVI"
        window.minSize = NSSize(width: 560, height: 420)
        window.collectionBehavior = [.fullScreenPrimary]
        super.init(window: window)
        isTwoPageView = DocumentHistoryStore.isTwoPageViewEnabled
        primaryPane.isTwoPageView = isTwoPageView
        setupContent()
        setupToolbar()
        setupPaneCallbacks(primaryPane)
        showPlaceholder()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        guard let window else { return }
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        statusField.translatesAutoresizingMaskIntoConstraints = false
        statusField.lineBreakMode = .byTruncatingMiddle
        statusField.textColor = .secondaryLabelColor
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        root.addSubview(contentContainer)
        root.addSubview(statusField)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: statusField.topAnchor),

            statusField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusField.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            statusField.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "macDVI.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }

    private func setupPaneCallbacks(_ pane: DocumentPane) {
        pane.onScroll = { [weak self, weak pane] _ in
            guard let self, let pane, self.isSyncLocked, !self.isSyncing else {
                self?.updateStatusForCurrentDocument()
                return
            }
            guard let sec = self.secondaryPane else { return }

            self.isSyncing = true
            defer { self.isSyncing = false }

            if pane === self.primaryPane {
                if let posA = self.primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(posA + self.alignmentOffset)
                }
            } else {
                if let posB = sec.continuousPosition {
                    self.primaryPane.scrollToContinuousPosition(posB - self.alignmentOffset)
                }
            }
            self.updateStatusForCurrentDocument()
        }

        pane.onPageChange = { [weak self] _ in
            self?.updateStatusForCurrentDocument()
        }

        pane.onScaleChange = { [weak self] _ in
            self?.updateStatusForCurrentDocument()
        }

        pane.onPaneActivated = { [weak self] activatedPane in
            self?.updatePaneFocus(activePane: activatedPane)
        }

        pane.onSyncTeXBackward = { [weak self] result in
            let fileName = URL(fileURLWithPath: result.file).lastPathComponent
            self?.statusField.stringValue = "SyncTeX → \(fileName):\(result.line):\(result.column)"
        }
    }

    func updatePaneFocus(activePane: DocumentPane? = nil) {
        let active = activePane ?? focusedPane
        primaryPane.isFocused = (active === primaryPane)
        secondaryPane?.isFocused = (active === secondaryPane)
    }

    private func showPlaceholder() {
        let label = NSTextField(labelWithString: "Open a DVI, XDV, PostScript, or PDF file")
        label.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        replaceContent(with: label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])
        statusField.stringValue = "No document open"
    }

    private func replaceContent(with view: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(view)
    }

    private func layoutSinglePane() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        splitView.subviews.forEach { $0.removeFromSuperview() }

        let view = primaryPane.containerView
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func layoutSplitView() {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        splitView.subviews.forEach { $0.removeFromSuperview() }

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        splitView.addSubview(primaryPane.containerView)
        if let sec = secondaryPane {
            splitView.addSubview(sec.containerView)
        }

        contentContainer.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            guard let self, self.splitView.subviews.count >= 2 else { return }
            let mid = self.contentContainer.bounds.width / 2
            self.splitView.setPosition(mid, ofDividerAt: 0)
        }
    }

    func openDocument(url: URL) {
        if containsDocument(url: url) {
            focusDocument(url: url)
            return
        }
        if let delegate = NSApp.delegate as? AppDelegate,
           let existing = delegate.controller(for: url),
           existing !== self {
            existing.focusDocument(url: url)
            if currentURL == nil && secondaryPane == nil {
                window?.close()
            }
            return
        }
        saveCurrentPage()
        if secondaryPane == nil {
            layoutSinglePane()
        }
        primaryPane.load(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self.primaryPane.makeFirstResponder()
                self.updateStatusForCurrentDocument()
            case .failure:
                self.updateStatusForCurrentDocument()
            }
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["dvi", "xdv", "ps", "eps", "pdf"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocument(url: url)
        }
    }

    func openSideBySide(url: URL) {
        let sec = DocumentPane()
        sec.isTwoPageView = isTwoPageView
        sec.autoScales = primaryPane.autoScales
        sec.showHeader = true
        sec.showCloseButton = true
        sec.showSyncButton = false
        sec.onClose = { [weak self] in
            self?.closeSideBySide()
        }
        setupPaneCallbacks(sec)
        self.secondaryPane = sec

        primaryPane.showHeader = true
        primaryPane.showCloseButton = false
        primaryPane.showSyncButton = true
        primaryPane.onSyncToggle = { [weak self] in
            self?.toggleSyncLock()
        }

        // Initially in manual alignment mode (unlocked)
        isSyncLocked = false
        alignmentOffset = 0.0

        layoutSplitView()
        updatePaneFocus()
        updateSyncButtonUI()

        sec.load(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self.updatePaneFocus()
                self.updateSyncButtonUI()
                self.updateStatusForCurrentDocument()
            case .failure:
                self.updateStatusForCurrentDocument()
            }
        }
    }

    @objc func openSideBySide(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Select Document for Side by Side View"
        panel.allowedContentTypes = ["dvi", "xdv", "ps", "eps", "pdf"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openSideBySide(url: url)
        }
    }

    @objc func closeSideBySide(_ sender: Any? = nil) {
        guard let sec = secondaryPane else { return }
        sec.saveCurrentPage()
        sec.cleanUpObservers()
        secondaryPane = nil
        isSyncLocked = false
        alignmentOffset = 0.0
        primaryPane.showHeader = false
        primaryPane.showSyncButton = false
        layoutSinglePane()
        updatePaneFocus()
        updateStatusForCurrentDocument()
        window?.toolbar?.validateVisibleItems()
    }

    @objc func toggleSyncLock(_ sender: Any? = nil) {
        guard secondaryPane != nil else { return }
        if isSyncLocked {
            unlockSync()
        } else {
            lockSync()
        }
    }

    func lockSync() {
        guard let sec = secondaryPane else { return }
        let pPos = primaryPane.continuousPosition ?? 0.0
        let sPos = sec.continuousPosition ?? 0.0
        alignmentOffset = sPos - pPos
        isSyncLocked = true
        updateSyncButtonUI()
        updateStatusForCurrentDocument()
    }

    func unlockSync() {
        isSyncLocked = false
        updateSyncButtonUI()
        updateStatusForCurrentDocument()
    }

    @objc func resetAlignmentOffset(_ sender: Any? = nil) {
        guard let sec = secondaryPane else { return }
        alignmentOffset = 0.0
        if let pPos = primaryPane.continuousPosition {
            sec.scrollToContinuousPosition(pPos)
        }
        updateSyncButtonUI()
        updateStatusForCurrentDocument()
    }

    @objc func toggleSyncScrolling(_ sender: Any? = nil) {
        toggleSyncLock(sender)
    }

    private func updateSyncButtonUI() {
        let offsetStr: String
        if abs(alignmentOffset) < 0.05 {
            offsetStr = "0p"
        } else {
            let rounded = alignmentOffset.rounded()
            if abs(rounded - alignmentOffset) < 0.05 {
                offsetStr = String(format: "%+dp", Int(rounded))
            } else {
                offsetStr = String(format: "%+.1fp", alignmentOffset)
            }
        }
        primaryPane.setSyncState(isLocked: isSyncLocked, offsetText: offsetStr)
        window?.toolbar?.validateVisibleItems()
    }

    func saveCurrentPage() {
        primaryPane.saveCurrentPage()
        secondaryPane?.saveCurrentPage()
    }

    // MARK: - Synchronized Zoom & View

    @objc func zoomIn(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            let pPos = primaryPane.continuousPosition
            primaryPane.zoomIn()
            sec.zoomIn()
            if let pPos {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.zoomIn()
        }
        updateStatusForCurrentDocument()
    }

    @objc func zoomOut(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            let pPos = primaryPane.continuousPosition
            primaryPane.zoomOut()
            sec.zoomOut()
            if let pPos {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.zoomOut()
        }
        updateStatusForCurrentDocument()
    }

    @objc func actualSize(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            let pPos = primaryPane.continuousPosition
            primaryPane.actualSize()
            sec.actualSize()
            if let pPos {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.actualSize()
        }
        updateStatusForCurrentDocument()
    }

    @objc func zoomToFit(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            let pPos = primaryPane.continuousPosition
            primaryPane.zoomToFit()
            sec.zoomToFit()
            if let pPos {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.zoomToFit()
        }
        updateStatusForCurrentDocument()
    }

    func setTwoPageView(_ enabled: Bool) {
        guard isTwoPageView != enabled else { return }
        isTwoPageView = enabled
        DocumentHistoryStore.isTwoPageViewEnabled = enabled
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            let pPos = primaryPane.continuousPosition
            primaryPane.isTwoPageView = enabled
            sec.isTwoPageView = enabled
            if let pPos {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            primaryPane.isTwoPageView = enabled
            secondaryPane?.isTwoPageView = enabled
        }
        pageViewSegmentedControl?.selectedSegment = enabled ? 1 : 0
        updateStatusForCurrentDocument()
    }

    @objc func toggleTwoPageView(_ sender: Any?) {
        setTwoPageView(!isTwoPageView)
    }

    @objc func setSinglePageMode(_ sender: Any?) {
        setTwoPageView(false)
    }

    @objc func setTwoPagesMode(_ sender: Any?) {
        setTwoPageView(true)
    }

    @objc func pageViewModeSegmentChanged(_ sender: NSSegmentedControl) {
        setTwoPageView(sender.selectedSegment == 1)
    }

    // MARK: - Synchronized Navigation

    override func pageDown(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            if focusedPane === sec {
                sec.pageDown(sender)
                if let sPos = sec.continuousPosition {
                    primaryPane.scrollToContinuousPosition(sPos - alignmentOffset)
                }
            } else {
                primaryPane.pageDown(sender)
                if let pPos = primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(pPos + alignmentOffset)
                }
            }
        } else {
            focusedPane.pageDown(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    override func pageUp(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            if focusedPane === sec {
                sec.pageUp(sender)
                if let sPos = sec.continuousPosition {
                    primaryPane.scrollToContinuousPosition(sPos - alignmentOffset)
                }
            } else {
                primaryPane.pageUp(sender)
                if let pPos = primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(pPos + alignmentOffset)
                }
            }
        } else {
            focusedPane.pageUp(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    var canGoNextPage: Bool {
        focusedPane.canGoNextPage
    }

    var canGoPreviousPage: Bool {
        focusedPane.canGoPreviousPage
    }

    @objc func nextPage(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            if focusedPane === sec {
                sec.nextPage(sender)
                if let sPos = sec.continuousPosition {
                    primaryPane.scrollToContinuousPosition(sPos - alignmentOffset)
                }
            } else {
                primaryPane.nextPage(sender)
                if let pPos = primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(pPos + alignmentOffset)
                }
            }
        } else {
            focusedPane.nextPage(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    @objc func previousPage(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            if focusedPane === sec {
                sec.previousPage(sender)
                if let sPos = sec.continuousPosition {
                    primaryPane.scrollToContinuousPosition(sPos - alignmentOffset)
                }
            } else {
                primaryPane.previousPage(sender)
                if let pPos = primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(pPos + alignmentOffset)
                }
            }
        } else {
            focusedPane.previousPage(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    @objc func firstPage(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            primaryPane.firstPage(sender)
            if let pPos = primaryPane.continuousPosition {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.firstPage(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    @objc func lastPage(_ sender: Any?) {
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            primaryPane.lastPage(sender)
            if let pPos = primaryPane.continuousPosition {
                sec.scrollToContinuousPosition(pPos + alignmentOffset)
            }
        } else {
            focusedPane.lastPage(sender)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    @objc func goToPage(_ sender: Any?) {
        guard let window else { return }
        let targetPane = focusedPane
        let total = targetPane.totalPages
        let current = targetPane.currentPageNumber
        guard total > 0 else { return }

        let alert = NSAlert()
        let docName = targetPane.currentURL?.lastPathComponent ?? "Document"
        alert.messageText = "Go to Page — \(docName)"
        alert.informativeText = "Enter page number (1 to \(total)):"
        let goButton = alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        input.stringValue = "\(current)"
        input.alignment = .center
        input.target = goButton
        input.action = #selector(NSButton.performClick(_:))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        DispatchQueue.main.async {
            input.selectText(nil)
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  let pageNum = Int(input.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            self.jumpToPage(pageNum, on: targetPane)
        }
    }

    func jumpToPage(_ pageNumber: Int, on targetPane: DocumentPane? = nil) {
        let pane = targetPane ?? focusedPane
        if isSyncLocked, let sec = secondaryPane {
            isSyncing = true
            defer { isSyncing = false }
            pane.jumpToPage(pageNumber)
            if pane === sec {
                if let sPos = sec.continuousPosition {
                    primaryPane.scrollToContinuousPosition(sPos - alignmentOffset)
                }
            } else {
                if let pPos = primaryPane.continuousPosition {
                    sec.scrollToContinuousPosition(pPos + alignmentOffset)
                }
            }
        } else {
            pane.jumpToPage(pageNumber)
        }
        updatePaneFocus()
        updateStatusForCurrentDocument()
    }

    // MARK: - Search

    @objc func performFind(_ sender: Any?) {
        focusedPane.showFindBar()
    }

    @objc func findNext(_ sender: Any?) {
        focusedPane.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        focusedPane.findPrevious()
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        focusedPane.useSelectionForFind()
    }

    @objc func hideFindBar(_ sender: Any?) {
        focusedPane.hideFindBar()
    }

    // MARK: - SyncTeX

    @discardableResult
    func forwardSync(sourceFile: String, line: Int, column: Int? = nil) -> Bool {
        let pane = focusedPane
        if pane.forwardSync(sourceFile: sourceFile, line: line, column: column) {
            let fileName = (sourceFile as NSString).lastPathComponent
            statusField.stringValue = "SyncTeX ← \(fileName):\(line)"
            return true
        }
        if let sec = secondaryPane, sec !== pane {
            if sec.forwardSync(sourceFile: sourceFile, line: line, column: column) {
                let fileName = (sourceFile as NSString).lastPathComponent
                statusField.stringValue = "SyncTeX ← \(fileName):\(line)"
                return true
            }
        }
        return false
    }

    @objc func jumpToTeXSource(_ sender: Any?) {
        let pane = focusedPane
        guard let docURL = pane.currentURL else {
            NSSound.beep()
            return
        }

        let currentPage = pane.currentPageNumber
        guard currentPage > 0 else {
            NSSound.beep()
            return
        }

        let centerPoint = CGPoint(x: 200, y: 150)
        if let result = pane.backwardSync(page: currentPage, point: centerPoint) {
            let fileName = URL(fileURLWithPath: result.file).lastPathComponent
            statusField.stringValue = "SyncTeX → \(fileName):\(result.line)"
        } else if let parser = SyncTeXService.shared.parser(for: docURL),
                  let result = parser.backwardSync(page: currentPage, point: CGPoint(x: 100, y: 100)) {
            SyncTeXEditorOpener.open(file: result.file, line: result.line, column: result.column)
            let fileName = URL(fileURLWithPath: result.file).lastPathComponent
            statusField.stringValue = "SyncTeX → \(fileName):\(result.line)"
        } else {
            statusField.stringValue = "SyncTeX: No source position found for page \(currentPage)"
            NSSound.beep()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if focusedPane.isFindBarVisible {
            focusedPane.hideFindBar()
            return
        }
        super.cancelOperation(sender)
    }

    // MARK: - Status & Title

    private func updateStatusForCurrentDocument() {
        guard let primaryURL = primaryPane.currentURL else {
            statusField.stringValue = "No document open"
            window?.title = "macDVI"
            window?.representedURL = nil
            return
        }

        let pCurrent = primaryPane.currentPageNumber
        let pTotal = primaryPane.totalPages
        let pZoom = primaryPane.zoomFactor

        if let secondary = secondaryPane, let secURL = secondary.currentURL {
            let sCurrent = secondary.currentPageNumber
            let sTotal = secondary.totalPages

            window?.title = "\(primaryURL.lastPathComponent) ↔ \(secURL.lastPathComponent)"
            window?.representedURL = nil

            var parts: [String] = []
            parts.append("\(primaryURL.lastPathComponent) (Page \(pCurrent)/\(pTotal))")
            parts.append("↔")
            parts.append("\(secURL.lastPathComponent) (Page \(sCurrent)/\(sTotal))")
            parts.append("\(Int((pZoom * 100).rounded()))%")
            if isSyncLocked {
                let offsetStr = abs(alignmentOffset) < 0.05 ? "aligned" : String(format: "%+.1fp", alignmentOffset)
                parts.append("(Sync: \(offsetStr))")
            } else {
                parts.append("(Aligning - Sync Unlocked)")
            }
            statusField.stringValue = parts.joined(separator: " ")
        } else {
            window?.title = primaryURL.lastPathComponent
            window?.representedURL = primaryURL

            var parts: [String] = []
            if pTotal > 0 {
                if isTwoPageView && pTotal > 1 {
                    let second = min(pCurrent + 1, pTotal)
                    if second > pCurrent {
                        parts.append("Pages \(pCurrent)–\(second) of \(pTotal)")
                    } else {
                        parts.append("Page \(pCurrent) of \(pTotal)")
                    }
                } else {
                    parts.append("Page \(pCurrent) of \(pTotal)")
                }
            }
            parts.append(primaryURL.lastPathComponent)
            parts.append("\(Int((pZoom * 100).rounded()))%")
            statusField.stringValue = parts.joined(separator: " - ")
        }
    }
}

extension DocumentWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setSinglePageMode(_:)) {
            menuItem.state = isTwoPageView ? .off : .on
            return currentURL != nil
        }
        if menuItem.action == #selector(setTwoPagesMode(_:)) {
            menuItem.state = isTwoPageView ? .on : .off
            return currentURL != nil
        }
        if menuItem.action == #selector(toggleTwoPageView(_:)) {
            menuItem.state = isTwoPageView ? .on : .off
            return currentURL != nil
        }
        if menuItem.action == #selector(openSideBySide(_:)) {
            return currentURL != nil
        }
        if menuItem.action == #selector(closeSideBySide(_:)) {
            return secondaryPane != nil
        }
        if menuItem.action == #selector(toggleSyncLock(_:)) || menuItem.action == #selector(toggleSyncScrolling(_:)) {
            menuItem.title = isSyncLocked ? "Lock Sync" : "Lock Sync"
            menuItem.state = isSyncLocked ? .on : .off
            return secondaryPane != nil
        }
        if menuItem.action == #selector(resetAlignmentOffset(_:)) {
            return secondaryPane != nil
        }
        if menuItem.action == #selector(performFind(_:)) ||
            menuItem.action == #selector(findNext(_:)) ||
            menuItem.action == #selector(findPrevious(_:)) ||
            menuItem.action == #selector(useSelectionForFind(_:)) {
            return currentURL != nil
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

extension DocumentWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openDocument, .openSideBySide, .syncLock, .goToPage, .pageViewMode, .search, .flexibleSpace, .zoomOut, .actualSize, .zoomToFit, .zoomIn]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openDocument, .openSideBySide, .syncLock, .goToPage, .pageViewMode, .search, .flexibleSpace, .zoomOut, .actualSize, .zoomToFit, .zoomIn]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case .openDocument:
            item.label = "Open"
            item.paletteLabel = "Open Document"
            item.toolTip = "Open a DVI, XDV, PostScript, or PDF file"
            item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Open")
            item.action = #selector(openDocument(_:))
        case .openSideBySide:
            item.label = "Side by Side"
            item.paletteLabel = "Open Side by Side"
            item.toolTip = "Open second document side by side (⌥⌘O)"
            item.image = NSImage(systemSymbolName: "square.split.2x1", accessibilityDescription: "Side by Side")
            item.action = #selector(openSideBySide(_:))
        case .syncLock:
            item.label = isSyncLocked ? "Unlock Sync" : "Lock Sync"
            item.paletteLabel = "Lock / Unlock Sync"
            item.toolTip = isSyncLocked ? "Unlock to manually align pages (⌥⌘S)" : "Lock pages in sync (⌥⌘S)"
            item.image = NSImage(systemSymbolName: isSyncLocked ? "lock.fill" : "lock.open", accessibilityDescription: "Sync Lock")
            item.action = #selector(toggleSyncLock(_:))
        case .goToPage:
            item.label = "Go to Page"
            item.paletteLabel = "Go to Page"
            item.toolTip = "Jump to page number (⌥⌘G or ⌘J)"
            item.image = NSImage(systemSymbolName: "arrow.right.to.line", accessibilityDescription: "Go to page")
            item.action = #selector(goToPage(_:))
        case .pageViewMode:
            let seg = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Single Page")!,
                    NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Two Pages")!
                ],
                trackingMode: .selectOne,
                target: self,
                action: #selector(pageViewModeSegmentChanged(_:))
            )
            seg.selectedSegment = isTwoPageView ? 1 : 0
            seg.setToolTip("Single Page (⌥⌘1)", forSegment: 0)
            seg.setToolTip("Two Pages (⌥⌘2)", forSegment: 1)
            pageViewSegmentedControl = seg
            item.view = seg
            item.label = "Page View"
            item.paletteLabel = "Page View Mode"
            item.toolTip = "Switch between single page and two-page view"
        case .search:
            item.label = "Find"
            item.paletteLabel = "Find"
            item.toolTip = "Find in document (⌘F)"
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.action = #selector(performFind(_:))
        case .zoomOut:
            item.label = "Zoom Out"
            item.paletteLabel = "Zoom Out"
            item.toolTip = "Zoom out"
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom out")
            item.action = #selector(zoomOut(_:))
        case .actualSize:
            item.label = "Actual Size"
            item.paletteLabel = "Actual Size"
            item.toolTip = "Actual size (⌘0)"
            item.image = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "Actual size")
            item.action = #selector(actualSize(_:))
        case .zoomToFit:
            item.label = "Zoom to Fit"
            item.paletteLabel = "Zoom to Fit"
            item.toolTip = "Zoom to fit window (⌘9)"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.down.right.magnifyingglass", accessibilityDescription: "Zoom to fit")
            item.action = #selector(zoomToFit(_:))
        case .zoomIn:
            item.label = "Zoom In"
            item.paletteLabel = "Zoom In"
            item.toolTip = "Zoom in"
            item.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom in")
            item.action = #selector(zoomIn(_:))
        default:
            return nil
        }

        return item
    }
}

extension DocumentWindowController: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .syncLock {
            item.label = isSyncLocked ? "Unlock Sync" : "Lock Sync"
            item.paletteLabel = "Lock / Unlock Sync"
            item.image = NSImage(
                systemSymbolName: isSyncLocked ? "lock.fill" : "lock.open",
                accessibilityDescription: isSyncLocked ? "Unlock Sync" : "Lock Sync"
            )
            item.toolTip = isSyncLocked
                ? "Unlock to manually align pages (⌥⌘S)"
                : "Lock pages in sync at current alignment (⌥⌘S)"
            return secondaryPane != nil
        }
        return true
    }
}

extension DocumentWindowController: NSWindowDelegate {
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
    }
}

private extension NSToolbarItem.Identifier {
    static let openDocument = NSToolbarItem.Identifier("macDVI.toolbar.open")
    static let openSideBySide = NSToolbarItem.Identifier("macDVI.toolbar.openSideBySide")
    static let syncLock = NSToolbarItem.Identifier("macDVI.toolbar.syncLock")
    static let goToPage = NSToolbarItem.Identifier("macDVI.toolbar.goToPage")
    static let pageViewMode = NSToolbarItem.Identifier("macDVI.toolbar.pageViewMode")
    static let search = NSToolbarItem.Identifier("macDVI.toolbar.search")
    static let zoomOut = NSToolbarItem.Identifier("macDVI.toolbar.zoomOut")
    static let actualSize = NSToolbarItem.Identifier("macDVI.toolbar.actualSize")
    static let zoomToFit = NSToolbarItem.Identifier("macDVI.toolbar.zoomToFit")
    static let zoomIn = NSToolbarItem.Identifier("macDVI.toolbar.zoomIn")
}

extension URL {
    func matchesDocumentURL(_ other: URL) -> Bool {
        if self == other { return true }
        let p1 = self.standardizedFileURL.resolvingSymlinksInPath().path
        let p2 = other.standardizedFileURL.resolvingSymlinksInPath().path
        if p1 == p2 { return true }
        if let id1 = try? self.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           let id2 = try? other.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier {
            return (id1 as AnyObject).isEqual(id2)
        }
        return false
    }
}
