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

    var isTwoPageView: Bool = false {
        didSet {
            pdfView?.displayMode = isTwoPageView ? .twoUpContinuous : .singlePageContinuous
            pdfView?.displaysAsBook = false
            dviView?.isTwoPageView = isTwoPageView
            updateBadge()
        }
    }

    var autoScales: Bool = false {
        didSet {
            pdfView?.autoScales = autoScales
            dviView?.autoScales = autoScales
            if autoScales {
                dviView?.applyZoomToFit()
            }
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
        containerView.addSubview(contentContainer)

        let headerHeight = headerBar.heightAnchor.constraint(equalToConstant: 0)
        headerHeightConstraint = headerHeight

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

            contentContainer.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
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
        let pv = PDFView()
        self.pdfView = pv
        self.dviView = nil
        self.scrollView = nil

        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.autoScales = autoScales
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
                    self?.isRestoringPage = false
                }
            }
        }

        pdfPageChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pv,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.saveCurrentPage()
            self.updateBadge()
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
        dv.autoScales = autoScales
        sv.documentView = dv
        self.dviView = dv
        self.scrollView = sv

        replaceContent(with: sv)
        pinToContainer(sv)

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
                self?.isRestoringPage = false
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
        autoScales = false
        if let pv = pdfView {
            pv.scaleFactor = 1.0
        }
        if let dv = dviView {
            dv.zoom = 1.0
        }
        onScaleChange?(self)
    }

    func zoomToFit() {
        autoScales = true
        if let pv = pdfView {
            pv.autoScales = true
        }
        if let dv = dviView {
            dv.autoScales = true
            dv.applyZoomToFit()
        }
        onScaleChange?(self)
    }

    private func adjustZoom(by multiplier: CGFloat) {
        autoScales = false
        if let pv = pdfView {
            pv.autoScales = false
            pv.scaleFactor = min(max(pv.scaleFactor * multiplier, 0.1), 8.0)
        }
        if let dv = dviView {
            dv.autoScales = false
            dv.zoom *= multiplier
        }
        onScaleChange?(self)
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

    func nextPage(_ sender: Any?) {
        if let pv = pdfView {
            pv.goToNextPage(sender)
        }
        if let dv = dviView {
            dv.goToNextPage()
        }
        updateBadge()
    }

    func previousPage(_ sender: Any?) {
        if let pv = pdfView {
            pv.goToPreviousPage(sender)
        }
        if let dv = dviView {
            dv.goToPreviousPage()
        }
        updateBadge()
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
}
