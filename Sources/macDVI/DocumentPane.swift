import AppKit
import PDFKit

final class DocumentPane: NSObject {
    let containerView = NSView()
    private let contentContainer = NSView()
    private let headerBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pageBadge = NSTextField(labelWithString: "")
    let syncButton = NSButton()
    private let closeButton = NSButton()
    private let trailingStack = NSStackView()

    private(set) var currentURL: URL?
    private(set) var pdfView: PDFView?
    private(set) var dviView: DVIDocumentView?
    private(set) var scrollView: NSScrollView?

    private var pdfPageChangeObserver: NSObjectProtocol?
    private var pdfScaleChangeObserver: NSObjectProtocol?
    private var scrollViewBoundsObserver: NSObjectProtocol?
    private var isRestoringPage = false
    private var headerHeightConstraint: NSLayoutConstraint?

    let navigationHistory = PageNavigationHistory()
    private var isNavigatingHistory = false
    private var pageSettleTimer: Timer?

    let findBar = FindBarView()
    private var findBarHeightConstraint: NSLayoutConstraint?
    private let dviSearchEngine = DVISearchEngine()

    private(set) var searchQuery: String = ""
    private(set) var isCaseSensitive: Bool = false
    private var dviMatches: [DVISearchMatch] = []
    private var pdfMatches: [PDFSelection] = []
    private(set) var currentMatchIndex: Int = -1

    var isFindBarVisible: Bool {
        !findBar.isHidden
    }

    var isTwoPageView: Bool = false {
        didSet {
            pdfView?.displayMode = isTwoPageView ? .twoUpContinuous : .singlePageContinuous
            pdfView?.displaysAsBook = false
            dviView?.isTwoPageView = isTwoPageView
            if autoScaleMode == .width {
                fitWidth()
            } else if autoScaleMode == .height {
                fitHeight()
            }
            updateBadge()
        }
    }

    typealias AutoScaleMode = DocumentAutoScaleMode

    var autoScaleMode: AutoScaleMode = .none {
        didSet {
            guard autoScaleMode != .none else {
                pdfView?.autoScales = false
                dviView?.autoScaleMode = .none
                return
            }
            switch autoScaleMode {
            case .width:
                if let pv = pdfView { applyPDFZoomToFitWidth(pv) }
                dviView?.autoScaleMode = .width
            case .height:
                if let pv = pdfView { applyPDFZoomToFitHeight(pv) }
                dviView?.autoScaleMode = .height
            case .none:
                break
            }
        }
    }

    var autoScales: Bool {
        get { autoScaleMode != .none }
        set {
            autoScaleMode = newValue ? .width : .none
        }
    }

    var showHeader: Bool = false {
        didSet {
            headerBar.isHidden = !showHeader
            headerHeightConstraint?.constant = showHeader ? 30 : 0
        }
    }

    var showCloseButton: Bool = false {
        didSet {
            closeButton.isHidden = !showCloseButton
        }
    }

    var showSyncButton: Bool = false {
        didSet {
            syncButton.isHidden = !showSyncButton
        }
    }

    var isFocused: Bool = false {
        didSet {
            guard oldValue != isFocused else { return }
            titleLabel.textColor = isFocused ? .labelColor : .secondaryLabelColor
            titleLabel.font = .systemFont(ofSize: 12, weight: isFocused ? .bold : .medium)
            headerBar.layer?.backgroundColor = isFocused
                ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                : NSColor.windowBackgroundColor.cgColor
        }
    }

    var onClose: (() -> Void)?
    var onSyncToggle: (() -> Void)?
    var onPaneActivated: ((DocumentPane) -> Void)?
    var onScroll: ((DocumentPane) -> Void)?
    var onPageChange: ((DocumentPane) -> Void)?
    var onScaleChange: ((DocumentPane) -> Void)?
    var onSyncTeXBackward: ((SyncTeXResult) -> Void)?

    override init() {
        super.init()
        setupViews()
    }

    deinit {
        cleanUpObservers()
    }

    private func setupViews() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        headerBar.isHidden = true

        let headerClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(headerBarClicked))
        headerBar.addGestureRecognizer(headerClickRecognizer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle

        pageBadge.translatesAutoresizingMaskIntoConstraints = false
        pageBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pageBadge.textColor = .secondaryLabelColor

        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.bezelStyle = .roundRect
        syncButton.controlSize = .small
        syncButton.font = .systemFont(ofSize: 11, weight: .medium)
        syncButton.target = self
        syncButton.action = #selector(syncButtonClicked)
        syncButton.isHidden = true

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        closeButton.isHidden = true

        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8
        trailingStack.addArrangedSubview(pageBadge)
        trailingStack.addArrangedSubview(syncButton)
        trailingStack.addArrangedSubview(closeButton)

        headerBar.addSubview(titleLabel)
        headerBar.addSubview(trailingStack)

        let bottomBorder = NSBox()
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        bottomBorder.boxType = .separator
        headerBar.addSubview(bottomBorder)

        containerView.addSubview(headerBar)
        containerView.addSubview(findBar)
        containerView.addSubview(contentContainer)

        let headerHeight = headerBar.heightAnchor.constraint(equalToConstant: 0)
        headerHeightConstraint = headerHeight

        let findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        findBarHeightConstraint = findBarHeight
        findBar.isHidden = true

        findBar.onSearchTextChanged = { [weak self] text in
            guard let self else { return }
            self.performSearch(query: text, caseSensitive: self.findBar.isCaseSensitive)
        }
        findBar.onNextMatch = { [weak self] in
            self?.findNext()
        }
        findBar.onPreviousMatch = { [weak self] in
            self?.findPrevious()
        }
        findBar.onToggleMatchCase = { [weak self] isCase in
            guard let self else { return }
            self.performSearch(query: self.searchQuery, caseSensitive: isCase)
        }
        findBar.onClose = { [weak self] in
            self?.hideFindBar()
        }

        NSLayoutConstraint.activate([
            headerHeight,
            headerBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),

            trailingStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            trailingStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            bottomBorder.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),

            findBarHeight,
            findBar.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            contentContainer.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        contentContainer.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentContainerFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: contentContainer
        )
    }

    @objc private func contentContainerFrameDidChange() {
        guard autoScaleMode != .none else { return }
        switch autoScaleMode {
        case .width:
            if let pv = pdfView { applyPDFZoomToFitWidth(pv) }
            if let dv = dviView { dv.applyZoomToFitWidth() }
        case .height:
            if let pv = pdfView { applyPDFZoomToFitHeight(pv) }
            if let dv = dviView { dv.applyZoomToFitHeight() }
        case .none:
            break
        }
    }

    @objc private func headerBarClicked() {
        makeFirstResponder()
        onPaneActivated?(self)
    }

    @objc private func syncButtonClicked() {
        onSyncToggle?()
    }

    func setSyncState(isLocked: Bool, offsetText: String?) {
        if isLocked {
            let offsetSuffix = (offsetText != nil && !offsetText!.isEmpty) ? " (\(offsetText!))" : ""
            syncButton.title = "🔒 In Sync\(offsetSuffix)"
            syncButton.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
            syncButton.contentTintColor = .systemGreen
            syncButton.toolTip = "Sync is locked\(offsetSuffix). Click to unlock and manually align pages (⌥⌘S)"
        } else {
            syncButton.title = "🔓 Lock Sync"
            syncButton.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: "Unlocked")
            syncButton.contentTintColor = .systemBlue
            syncButton.toolTip = "Align pages manually, then click here to lock sync (⌥⌘S)"
        }
    }

    @objc private func closeButtonClicked() {
        onClose?()
    }

    func load(url: URL, completion: @escaping (Result<DVIDocumentLoadResult, Error>) -> Void) {
        saveCurrentPage()
        currentURL = url
        dviSearchEngine.clearCache()
        titleLabel.stringValue = url.lastPathComponent
        showLoading(message: "Opening \(url.lastPathComponent)...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DVIDocumentLoader.load(url: url) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let loadResult):
                    switch loadResult {
                    case .pdf(let conversion):
                        self.showPDF(url: conversion.pdfURL, originalURL: url)
                    case .native(let document):
                        self.showNative(document: document)
                    }
                    self.updateBadge()
                    if self.isFindBarVisible && !self.searchQuery.isEmpty {
                        self.performSearch(query: self.searchQuery, caseSensitive: self.isCaseSensitive)
                    }
                    completion(.success(loadResult))
                case .failure(let error):
                    self.showError(error)
                    completion(.failure(error))
                }
            }
        }
    }

    private func showLoading(message: String) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.textColor = .secondaryLabelColor

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        replaceContent(with: stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor)
        ])
    }

    private func showError(_ error: Error) {
        let label = NSTextField(wrappingLabelWithString: error.localizedDescription)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        replaceContent(with: label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: contentContainer.widthAnchor, multiplier: 0.8)
        ])
    }

    private func showPDF(url: URL, originalURL: URL) {
        cleanUpObservers()
        let pv = MacDVIPDFView()
        self.pdfView = pv
        self.dviView = nil
        self.scrollView = nil

        pv.onCommandClick = { [weak self] pagePoint, page in
            guard let self, let doc = self.pdfView?.document else { return }
            let pageIdx = doc.index(for: page)
            guard pageIdx != NSNotFound else { return }
            let pageNum = pageIdx + 1
            let bounds = page.bounds(for: .cropBox)
            let synctexY = bounds.height - pagePoint.y
            let synctexPt = CGPoint(x: pagePoint.x, y: synctexY)
            if let result = self.backwardSync(page: pageNum, point: synctexPt) {
                let pdfY = bounds.height - result.rect.maxY
                let pdfRect = CGRect(x: result.rect.minX, y: pdfY, width: result.rect.width, height: result.rect.height)
                (self.pdfView as? MacDVIPDFView)?.showHighlight(rect: pdfRect, on: page)
            }
        }

        pv.translatesAutoresizingMaskIntoConstraints = false
        if autoScaleMode == .width {
            applyPDFZoomToFitWidth(pv)
        } else if autoScaleMode == .height {
            applyPDFZoomToFitHeight(pv)
        } else {
            pv.autoScales = false
        }
        pv.displayMode = isTwoPageView ? .twoUpContinuous : .singlePageContinuous
        pv.displaysAsBook = false
        pv.displaysPageBreaks = true
        pv.backgroundColor = .windowBackgroundColor

        let document = PDFDocument(url: url)
        pv.document = document
        replaceContent(with: pv)
        pinToContainer(pv)

        let targetIndex: Int
        if let saved = DocumentHistoryStore.lastViewedPage(for: originalURL),
           let count = document?.pageCount, saved >= 0 && saved < count {
            targetIndex = saved
        } else {
            targetIndex = 0
        }

        if let targetPage = document?.page(at: targetIndex) {
            isRestoringPage = true
            positionPDFViewAtTop(pv, page: targetPage)
            DispatchQueue.main.async { [weak self, weak pv] in
                guard let self, let pv else { return }
                self.positionPDFViewAtTop(pv, page: targetPage)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isRestoringPage = false
                    self.navigationHistory.clear()
                    self.navigationHistory.record(pageNumber: targetIndex + 1)
                }
            }
        } else {
            navigationHistory.clear()
            navigationHistory.record(pageNumber: 1)
        }

        pdfPageChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pv,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.saveCurrentPage()
            self.updateBadge()
            self.schedulePageSettleRecording()
            self.onPageChange?(self)
        }

        pdfScaleChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged,
            object: pv,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onScaleChange?(self)
        }

        // Attach scroll clip view observer for live scroll synchronization
        if let scroll = pv.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.isRestoringPage else { return }
                self.onScroll?(self)
            }
        }
    }

    private func showNative(document: DVIDocument) {
        cleanUpObservers()
        self.pdfView = nil

        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers = false
        sv.backgroundColor = .windowBackgroundColor
        sv.drawsBackground = true

        let dv = DVIDocumentView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        dv.document = document
        dv.isTwoPageView = isTwoPageView
        dv.onCommandClick = { [weak self] pageIndex, pt in
            guard let self else { return }
            let pageNum = pageIndex + 1
            if let result = self.backwardSync(page: pageNum, point: pt) {
                self.dviView?.showSyncTeXHighlight(pageIndex: pageIndex, rect: result.rect)
            }
        }
        sv.documentView = dv
        self.dviView = dv
        self.scrollView = sv

        replaceContent(with: sv)
        pinToContainer(sv)
        dv.autoScaleMode = autoScaleMode

        let targetIndex: Int
        if let saved = DocumentHistoryStore.lastViewedPage(for: document.url),
           saved >= 0 && saved < document.pages.count {
            targetIndex = saved
        } else {
            targetIndex = 0
        }

        isRestoringPage = true
        dv.scrollToPage(index: targetIndex)
        DispatchQueue.main.async { [weak self, weak dv] in
            guard let self, let dv else { return }
            dv.scrollToPage(index: targetIndex)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRestoringPage = false
                self.navigationHistory.clear()
                self.navigationHistory.record(pageNumber: targetIndex + 1)
            }
        }

        sv.contentView.postsBoundsChangedNotifications = true
        scrollViewBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: sv.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isRestoringPage else { return }
            self.saveCurrentPage()
            self.updateBadge()
            self.schedulePageSettleRecording()
            self.onScroll?(self)
            self.onPageChange?(self)
        }
    }

    private func replaceContent(with view: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(view)
    }

    private func pinToContainer(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func positionPDFViewAtTop(_ pv: PDFView, page: PDFPage) {
        containerView.window?.contentView?.layoutSubtreeIfNeeded()
        pv.layoutDocumentView()

        let pageBounds = page.bounds(for: pv.displayBox)
        let topOfPage = PDFDestination(
            page: page,
            at: CGPoint(x: pageBounds.midX, y: pageBounds.maxY)
        )
        pv.go(to: topOfPage)
    }

    func cleanUpObservers() {
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: contentContainer)
        pageSettleTimer?.invalidate()
        pageSettleTimer = nil
        if let o = pdfPageChangeObserver {
            NotificationCenter.default.removeObserver(o)
            pdfPageChangeObserver = nil
        }
        if let o = pdfScaleChangeObserver {
            NotificationCenter.default.removeObserver(o)
            pdfScaleChangeObserver = nil
        }
        if let o = scrollViewBoundsObserver {
            NotificationCenter.default.removeObserver(o)
            scrollViewBoundsObserver = nil
        }
    }

    func saveCurrentPage() {
        guard let currentURL, !isRestoringPage else { return }
        let index = currentPageIndex
        if index >= 0 {
            DocumentHistoryStore.setLastViewedPage(index, for: currentURL)
        }
    }

    func updateBadge() {
        let total = totalPages
        let current = currentPageNumber
        guard total > 0 else {
            pageBadge.stringValue = ""
            return
        }
        if isTwoPageView && total > 1 {
            let second = min(current + 1, total)
            if second > current {
                pageBadge.stringValue = "Pages \(current)–\(second) of \(total)"
            } else {
                pageBadge.stringValue = "Page \(current) of \(total)"
            }
        } else {
            pageBadge.stringValue = "Page \(current) of \(total)"
        }
    }

    func makeFirstResponder() {
        if let pv = pdfView {
            containerView.window?.makeFirstResponder(pv)
        } else if let dv = dviView {
            containerView.window?.makeFirstResponder(dv)
        }
    }

    // MARK: - Navigation & Zoom

    func zoomIn() {
        adjustZoom(by: 1.2)
    }

    func zoomOut() {
        adjustZoom(by: 1.0 / 1.2)
    }

    func actualSize() {
        autoScaleMode = .none
        if let pv = pdfView {
            pv.autoScales = false
            pv.scaleFactor = 1.0
        }
        if let dv = dviView {
            dv.autoScaleMode = .none
            dv.zoom = 1.0
        }
        onScaleChange?(self)
    }

    func zoomToFit() {
        fitWidth()
    }

    func zoomToFitWidth() {
        fitWidth()
    }

    func zoomToFitHeight() {
        fitHeight()
    }

    func fitWidth() {
        autoScaleMode = .width
        if let pv = pdfView {
            applyPDFZoomToFitWidth(pv)
        }
        if let dv = dviView {
            dv.autoScaleMode = .width
        }
        onScaleChange?(self)
    }

    func fitHeight() {
        autoScaleMode = .height
        if let pv = pdfView {
            applyPDFZoomToFitHeight(pv)
        }
        if let dv = dviView {
            dv.autoScaleMode = .height
        }
        onScaleChange?(self)
    }

    private func adjustZoom(by multiplier: CGFloat) {
        autoScaleMode = .none
        if let pv = pdfView {
            pv.autoScales = false
            pv.scaleFactor = min(max(pv.scaleFactor * multiplier, 0.1), 8.0)
        }
        if let dv = dviView {
            dv.autoScaleMode = .none
            dv.zoom *= multiplier
        }
        onScaleChange?(self)
    }

    private func applyPDFZoomToFitWidth(_ pv: PDFView) {
        guard let doc = pv.document, doc.pageCount > 0 else { return }
        guard let page = pv.currentPage ?? doc.page(at: 0) else { return }
        let pageBounds = page.bounds(for: pv.displayBox)
        var pageWidth = pageBounds.width
        if page.rotation == 90 || page.rotation == 270 {
            pageWidth = pageBounds.height
        }
        if isTwoPageView {
            pageWidth = pageWidth * 2 + 16
        }
        let viewportWidth = contentContainer.bounds.width
        guard viewportWidth > 50 else {
            DispatchQueue.main.async { [weak self, weak pv] in
                guard let self, let pv, self.autoScaleMode == .width else { return }
                self.applyPDFZoomToFitWidth(pv)
            }
            return
        }
        // Reserve space for margins and potential vertical scrollbar
        let availableWidth = max(viewportWidth - 32, 50)
        let scale = availableWidth / max(pageWidth, 1)
        pv.autoScales = false
        pv.scaleFactor = min(max(scale, 0.1), 8.0)
    }

    private func applyPDFZoomToFitHeight(_ pv: PDFView) {
        guard let doc = pv.document, doc.pageCount > 0 else { return }
        guard let page = pv.currentPage ?? doc.page(at: 0) else { return }
        let pageBounds = page.bounds(for: pv.displayBox)
        var pageHeight = pageBounds.height
        if page.rotation == 90 || page.rotation == 270 {
            pageHeight = pageBounds.width
        }
        let viewportHeight = contentContainer.bounds.height
        guard viewportHeight > 50 else {
            DispatchQueue.main.async { [weak self, weak pv] in
                guard let self, let pv, self.autoScaleMode == .height else { return }
                self.applyPDFZoomToFitHeight(pv)
            }
            return
        }
        // Reserve space for top/bottom margins and potential horizontal scrollbar
        let availableHeight = max(viewportHeight - 36, 50)
        let scale = availableHeight / max(pageHeight, 1)
        pv.autoScales = false
        pv.scaleFactor = min(max(scale, 0.1), 8.0)
    }

    func pageDown(_ sender: Any?) {
        if let pv = pdfView {
            pv.pageDown(sender)
        }
        if let dv = dviView {
            dv.scrollPageDown()
        }
        updateBadge()
    }

    func pageUp(_ sender: Any?) {
        if let pv = pdfView {
            pv.pageUp(sender)
        }
        if let dv = dviView {
            dv.scrollPageUp()
        }
        updateBadge()
    }

    var canGoNextPage: Bool {
        navigationHistory.canGoForward
    }

    var canGoPreviousPage: Bool {
        let current = currentPageNumber
        if current > 0 && navigationHistory.currentPage != current && navigationHistory.currentPage != nil {
            return true
        }
        return navigationHistory.canGoBack
    }

    func nextPage(_ sender: Any? = nil) {
        guard navigationHistory.canGoForward, let targetPage = navigationHistory.goForward() else {
            return
        }
        pageSettleTimer?.invalidate()
        isNavigatingHistory = true
        jumpToPageInternal(targetPage)
        isNavigatingHistory = false
        updateBadge()
        onPageChange?(self)
    }

    func previousPage(_ sender: Any? = nil) {
        let current = currentPageNumber
        if current > 0 && navigationHistory.currentPage != current {
            navigationHistory.record(pageNumber: current)
        }

        guard navigationHistory.canGoBack, let targetPage = navigationHistory.goBack() else {
            return
        }
        pageSettleTimer?.invalidate()
        isNavigatingHistory = true
        jumpToPageInternal(targetPage)
        isNavigatingHistory = false
        updateBadge()
        onPageChange?(self)
    }

    func firstPage(_ sender: Any?) {
        if let pv = pdfView {
            pv.goToFirstPage(sender)
        }
        if let dv = dviView {
            dv.scrollToTop()
        }
        updateBadge()
    }

    func lastPage(_ sender: Any?) {
        if let pv = pdfView {
            pv.goToLastPage(sender)
        }
        if let dv = dviView {
            dv.scrollToBottom()
        }
        updateBadge()
    }

    func jumpToPage(_ pageNumber: Int) {
        let count = totalPages
        guard count > 0 else { return }
        let clamped = max(min(pageNumber, count), 1)

        if !isNavigatingHistory {
            pageSettleTimer?.invalidate()
            let current = currentPageNumber
            if current > 0 && navigationHistory.currentPage != current {
                navigationHistory.record(pageNumber: current)
            }
            navigationHistory.record(pageNumber: clamped)
        }

        jumpToPageInternal(clamped)
    }

    private func jumpToPageInternal(_ pageNumber: Int) {
        let count = totalPages
        guard count > 0 else { return }
        let clamped = max(min(pageNumber, count), 1)
        let targetIndex = clamped - 1

        if let dv = dviView {
            dv.scrollToPage(index: targetIndex)
            saveCurrentPage()
            updateBadge()
        } else if let pv = pdfView, let doc = pv.document, let targetPage = doc.page(at: targetIndex) {
            positionPDFViewAtTop(pv, page: targetPage)
            saveCurrentPage()
            updateBadge()
        }
    }

    private func schedulePageSettleRecording() {
        guard !isNavigatingHistory && !isRestoringPage else { return }
        pageSettleTimer?.invalidate()
        pageSettleTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, !self.isNavigatingHistory && !self.isRestoringPage else { return }
            let current = self.currentPageNumber
            if current > 0 {
                self.navigationHistory.record(pageNumber: current)
            }
        }
    }

    var currentPageIndex: Int {
        if let pv = pdfView, let doc = pv.document {
            if let dest = pv.currentDestination, let destPage = dest.page {
                let idx = doc.index(for: destPage)
                if idx >= 0 { return idx }
            }
            if let currentPage = pv.currentPage {
                let idx = doc.index(for: currentPage)
                return idx >= 0 ? idx : 0
            }
        } else if let dv = dviView {
            return dv.currentPageIndex
        }
        return 0
    }

    var currentPageNumber: Int {
        currentPageIndex + 1
    }

    var totalPages: Int {
        if let pv = pdfView, let doc = pv.document {
            return doc.pageCount
        } else if let dv = dviView, let doc = dv.document {
            return doc.pages.count
        }
        return 0
    }

    var zoomFactor: CGFloat {
        if let pv = pdfView {
            return pv.scaleFactor
        } else if let dv = dviView {
            return dv.zoom
        }
        return 1.0
    }

    // MARK: - Synchronized Scrolling Helpers

    var continuousPosition: Double? {
        guard let pos = currentScrollPosition() else { return nil }
        return Double(pos.pageIndex) + Double(pos.progress)
    }

    func scrollToContinuousPosition(_ pos: Double) {
        guard totalPages > 0 else { return }
        let maxPos = Double(max(totalPages - 1, 0))
        let clamped = max(0.0, min(pos, maxPos + 0.999))
        let pageIndex = Int(floor(clamped))
        let progress = CGFloat(clamped - Double(pageIndex))
        scrollToPosition(pageIndex: pageIndex, progress: progress)
    }

    func currentScrollPosition() -> (pageIndex: Int, progress: CGFloat)? {
        if let pv = pdfView, let doc = pv.document {
            if let dest = pv.currentDestination, let destPage = dest.page {
                let pageIndex = doc.index(for: destPage)
                guard pageIndex >= 0 else { return nil }
                let bounds = destPage.bounds(for: pv.displayBox)
                let pointY = dest.point.y
                let progress = max(min((bounds.maxY - pointY) / max(bounds.height, 1), 1.0), 0.0)
                return (pageIndex, progress)
            } else if let currentPage = pv.currentPage {
                let pageIndex = doc.index(for: currentPage)
                guard pageIndex >= 0 else { return nil }
                return (pageIndex, 0.0)
            }
        } else if let dv = dviView {
            return dv.currentScrollPosition()
        }
        return nil
    }

    func scrollToPosition(pageIndex: Int, progress: CGFloat) {
        if let pv = pdfView, let doc = pv.document {
            let clampedIndex = max(min(pageIndex, doc.pageCount - 1), 0)
            if let page = doc.page(at: clampedIndex) {
                let bounds = page.bounds(for: pv.displayBox)
                let targetPointY = bounds.maxY - progress * bounds.height
                let dest = PDFDestination(page: page, at: CGPoint(x: kPDFDestinationUnspecifiedValue, y: targetPointY))
                pv.go(to: dest)
                updateBadge()
            }
        } else if let dv = dviView {
            dv.scrollToPosition(pageIndex: pageIndex, progress: progress)
            updateBadge()
        }
    }

    // MARK: - Search

    func showFindBar() {
        findBar.isHidden = false
        findBarHeightConstraint?.constant = 38
        findBar.makeSearchFieldFirstResponder()
        if !searchQuery.isEmpty {
            performSearch(query: searchQuery, caseSensitive: isCaseSensitive)
        }
    }

    func hideFindBar() {
        findBar.isHidden = true
        findBarHeightConstraint?.constant = 0
        clearSearchHighlights()
        makeFirstResponder()
    }

    func toggleFindBar() {
        if isFindBarVisible {
            hideFindBar()
        } else {
            showFindBar()
        }
    }

    func useSelectionForFind() {
        var queryToUse: String? = nil
        if let pv = pdfView, let sel = pv.currentSelection?.string, !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryToUse = sel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let query = queryToUse {
            showFindBar()
            findBar.setQuery(query)
        } else if !isFindBarVisible {
            showFindBar()
        }
    }

    var totalMatches: Int {
        if pdfView != nil {
            return pdfMatches.count
        } else if dviView != nil {
            return dviMatches.count
        }
        return 0
    }

    func performSearch(query: String, caseSensitive: Bool) {
        searchQuery = query
        isCaseSensitive = caseSensitive

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clearSearchHighlights()
            currentMatchIndex = -1
            findBar.updateMatchStatus(currentIndex: -1, totalMatches: 0, hasQuery: false)
            return
        }

        if let pv = pdfView, let doc = pv.document {
            var options: NSString.CompareOptions = [.literal]
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            let selections = doc.findString(trimmed, withOptions: options)
            pdfMatches = selections
            dviMatches = []
            pv.highlightedSelections = selections

            if selections.isEmpty {
                currentMatchIndex = -1
                pv.clearSelection()
            } else {
                currentMatchIndex = 0
                jumpToPDFMatch(at: 0)
            }
            findBar.updateMatchStatus(currentIndex: currentMatchIndex, totalMatches: selections.count, hasQuery: true)
        } else if let dv = dviView, let doc = dv.document {
            let matches = dviSearchEngine.search(document: doc, query: trimmed, caseSensitive: caseSensitive)
            dviMatches = matches
            pdfMatches = []
            dv.searchMatches = matches

            if matches.isEmpty {
                currentMatchIndex = -1
                dv.activeSearchMatchIndex = -1
            } else {
                currentMatchIndex = 0
                jumpToDVIMatch(at: 0)
            }
            findBar.updateMatchStatus(currentIndex: currentMatchIndex, totalMatches: matches.count, hasQuery: true)
        }
    }

    func findNext() {
        let total = totalMatches
        guard total > 0 else {
            if !isFindBarVisible {
                showFindBar()
            }
            return
        }
        let nextIndex = (currentMatchIndex + 1) % total
        currentMatchIndex = nextIndex
        jumpToMatch(at: nextIndex)
        findBar.updateMatchStatus(currentIndex: currentMatchIndex, totalMatches: total, hasQuery: true)
    }

    func findPrevious() {
        let total = totalMatches
        guard total > 0 else {
            if !isFindBarVisible {
                showFindBar()
            }
            return
        }
        let prevIndex = (currentMatchIndex - 1 + total) % total
        currentMatchIndex = prevIndex
        jumpToMatch(at: prevIndex)
        findBar.updateMatchStatus(currentIndex: currentMatchIndex, totalMatches: total, hasQuery: true)
    }

    func jumpToMatch(at index: Int) {
        if pdfView != nil {
            jumpToPDFMatch(at: index)
        } else if dviView != nil {
            jumpToDVIMatch(at: index)
        }
    }

    private func jumpToPDFMatch(at index: Int) {
        guard let pv = pdfView, let doc = pv.document, index >= 0, index < pdfMatches.count else { return }
        let sel = pdfMatches[index]
        if let page = sel.pages.first {
            let pageNum = doc.index(for: page) + 1
            if pageNum > 0 {
                let current = currentPageNumber
                if current > 0 && navigationHistory.currentPage != current {
                    navigationHistory.record(pageNumber: current)
                }
                navigationHistory.record(pageNumber: pageNum)
            }
        }
        pv.setCurrentSelection(sel, animate: true)
        pv.go(to: sel)
        pv.scrollSelectionToVisible(nil)
        updateBadge()
        onPageChange?(self)
    }

    private func jumpToDVIMatch(at index: Int) {
        guard let dv = dviView, index >= 0, index < dviMatches.count else { return }
        dv.activeSearchMatchIndex = index
        let match = dviMatches[index]
        let pageNum = match.pageIndex + 1
        if pageNum > 0 {
            let current = currentPageNumber
            if current > 0 && navigationHistory.currentPage != current {
                navigationHistory.record(pageNumber: current)
            }
            navigationHistory.record(pageNumber: pageNum)
        }
        dv.scrollToSearchMatch(match)
        updateBadge()
        onPageChange?(self)
    }

    func clearSearchHighlights() {
        if let pv = pdfView {
            pv.highlightedSelections = nil
            pv.clearSelection()
        }
        if let dv = dviView {
            dv.searchMatches = []
            dv.activeSearchMatchIndex = -1
        }
        pdfMatches = []
        dviMatches = []
    }

    // MARK: - SyncTeX Synchronization

    @discardableResult
    func forwardSync(sourceFile: String, line: Int, column: Int? = nil) -> Bool {
        guard let currentURL else { return false }
        guard let result = SyncTeXService.shared.forwardSync(
            documentURL: currentURL,
            sourceFile: sourceFile,
            line: line,
            column: column
        ) else {
            return false
        }

        let targetPageNum = result.page
        let current = currentPageNumber
        if current > 0 && navigationHistory.currentPage != current {
            navigationHistory.record(pageNumber: current)
        }
        navigationHistory.record(pageNumber: targetPageNum)

        let pageIndex = result.page - 1
        if let dv = dviView {
            dv.scrollToSyncTeX(pageIndex: pageIndex, rect: result.rect)
            updateBadge()
            onPageChange?(self)
            return true
        }

        if let pv = pdfView as? MacDVIPDFView,
           let page = pv.document?.page(at: pageIndex) {
            let bounds = page.bounds(for: .cropBox)
            let pdfY = bounds.height - result.rect.maxY
            let pdfRect = CGRect(x: result.rect.minX, y: pdfY, width: result.rect.width, height: result.rect.height)
            pv.showHighlight(rect: pdfRect, on: page)
            updateBadge()
            onPageChange?(self)
            return true
        }

        return false
    }

    @discardableResult
    func backwardSync(page: Int, point: CGPoint) -> SyncTeXResult? {
        guard let currentURL else { return nil }
        guard let result = SyncTeXService.shared.backwardSync(
            documentURL: currentURL,
            page: page,
            point: point
        ) else {
            return nil
        }

        SyncTeXEditorOpener.open(file: result.file, line: result.line, column: result.column)
        onSyncTeXBackward?(result)
        return result
    }
}

// MARK: - MacDVIPDFView

final class MacDVIPDFView: PDFView {
    var onCommandClick: ((CGPoint, PDFPage) -> Void)?
    private var highlightOverlayView: NSView?
    private var highlightTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let windowPoint = event.locationInWindow
            let viewPoint = convert(windowPoint, from: nil)
            if let page = page(for: viewPoint, nearest: false) {
                let pagePoint = convert(viewPoint, to: page)
                onCommandClick?(pagePoint, page)
                return
            }
        }
        super.mouseDown(with: event)
    }

    func showHighlight(rect: CGRect, on page: PDFPage) {
        highlightTimer?.invalidate()
        highlightOverlayView?.removeFromSuperview()

        go(to: rect, on: page)

        let targetParent = documentView ?? self
        let viewRect = convert(rect, from: page)
        let parentRect = (documentView != nil) ? convert(viewRect, to: targetParent) : viewRect

        let overlay = NSView(frame: parentRect)
        overlay.wantsLayer = true
        let color = AppSettings.shared.highlightColor.color
        overlay.layer?.backgroundColor = color.withAlphaComponent(0.35).cgColor
        overlay.layer?.borderColor = color.withAlphaComponent(0.85).cgColor
        overlay.layer?.borderWidth = 1.5
        overlay.layer?.cornerRadius = 3.0

        targetParent.addSubview(overlay)
        highlightOverlayView = overlay

        let duration = AppSettings.shared.highlightDuration
        highlightTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak overlay] _ in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                overlay?.animator().alphaValue = 0.0
            } completionHandler: {
                overlay?.removeFromSuperview()
                if self?.highlightOverlayView === overlay {
                    self?.highlightOverlayView = nil
                }
            }
        }
    }
}
