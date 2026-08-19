import AppKit
import UniformTypeIdentifiers
import PDFKit

final class DocumentWindowController: NSWindowController {
    private let contentContainer = NSView()
    private let statusField = NSTextField(labelWithString: "Open a document")
    private var pdfView: PDFView?
    private var dviView: DVIDocumentView?
    private var currentURL: URL?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "macDVI"
        window.minSize = NSSize(width: 560, height: 420)
        super.init(window: window)
        setupContent()
        setupToolbar()
        showPlaceholder()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func openDocument(url: URL) {
        currentURL = url
        window?.title = url.lastPathComponent
        showLoading(message: "Opening \(url.lastPathComponent)...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DVIDocumentLoader.load(url: url) }
            DispatchQueue.main.async {
                self?.handleLoadResult(result, url: url)
            }
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["dvi", "xdv", "ps", "eps"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocument(url: url)
        }
    }

    @objc func zoomIn(_ sender: Any?) {
        adjustZoom(by: 1.2)
    }

    @objc func zoomOut(_ sender: Any?) {
        adjustZoom(by: 1.0 / 1.2)
    }

    @objc func actualSize(_ sender: Any?) {
        if let pdfView {
            pdfView.scaleFactor = 1.0
        }
        if let dviView {
            dviView.zoom = 1.0
        }
        updateStatusForCurrentDocument()
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

    private func handleLoadResult(_ result: Result<DVIDocumentLoadResult, Error>, url: URL) {
        switch result {
        case .success(.pdf(let conversion)):
            showPDF(url: conversion.pdfURL)
            statusField.stringValue = "Rendered \(url.lastPathComponent) with \(conversion.converterName)"
        case .success(.native(let document)):
            showNative(document: document)
            var status = "Rendered \(url.lastPathComponent) with native renderer"
            if !document.warnings.isEmpty {
                status += " - \(document.warnings.count) warning(s)"
            }
            statusField.stringValue = status
        case .failure(let error):
            showError(error)
        }
    }

    private func showPlaceholder() {
        let label = NSTextField(labelWithString: "Open a DVI, XDV, or PostScript file")
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

    private func showLoading(message: String) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .large
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
        statusField.stringValue = message
    }

    private func showPDF(url: URL) {
        pdfView = PDFView()
        dviView = nil
        guard let pdfView else { return }
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .windowBackgroundColor
        let document = PDFDocument(url: url)
        pdfView.document = document
        replaceContent(with: pdfView)
        pinToContainer(pdfView)
        if let firstPage = document?.page(at: 0) {
            positionPDFViewAtTop(pdfView, page: firstPage)
            DispatchQueue.main.async { [weak self, weak pdfView] in
                guard let self, let pdfView else { return }
                self.positionPDFViewAtTop(pdfView, page: firstPage)
            }
        }
    }

    private func positionPDFViewAtTop(_ pdfView: PDFView, page: PDFPage) {
        window?.contentView?.layoutSubtreeIfNeeded()
        pdfView.layoutDocumentView()

        let pageBounds = page.bounds(for: pdfView.displayBox)
        let topOfPage = PDFDestination(
            page: page,
            at: CGPoint(x: pageBounds.midX, y: pageBounds.maxY)
        )
        pdfView.go(to: topOfPage)
    }

    private func showNative(document: DVIDocument) {
        pdfView = nil

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.drawsBackground = true

        let dviView = DVIDocumentView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        dviView.document = document
        scrollView.documentView = dviView
        self.dviView = dviView

        replaceContent(with: scrollView)
        pinToContainer(scrollView)
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
            label.widthAnchor.constraint(lessThanOrEqualTo: contentContainer.widthAnchor, multiplier: 0.72)
        ])
        statusField.stringValue = "Could not open document"
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

    private func adjustZoom(by multiplier: CGFloat) {
        if let pdfView {
            pdfView.autoScales = false
            pdfView.scaleFactor = min(max(pdfView.scaleFactor * multiplier, 0.1), 8.0)
        }
        if let dviView {
            dviView.zoom *= multiplier
        }
        updateStatusForCurrentDocument()
    }

    private func updateStatusForCurrentDocument() {
        guard let currentURL else { return }
        let zoom: CGFloat
        if let pdfView {
            zoom = pdfView.scaleFactor
        } else {
            zoom = dviView?.zoom ?? 1
        }
        statusField.stringValue = "\(currentURL.lastPathComponent) - \(Int((zoom * 100).rounded()))%"
    }
}

extension DocumentWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openDocument, .flexibleSpace, .zoomOut, .actualSize, .zoomIn]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.openDocument, .flexibleSpace, .zoomOut, .actualSize, .zoomIn]
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
            item.toolTip = "Open a DVI, XDV, or PostScript file"
            item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Open")
            item.action = #selector(openDocument(_:))
        case .zoomOut:
            item.label = "Zoom Out"
            item.paletteLabel = "Zoom Out"
            item.toolTip = "Zoom out"
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom out")
            item.action = #selector(zoomOut(_:))
        case .actualSize:
            item.label = "Actual Size"
            item.paletteLabel = "Actual Size"
            item.toolTip = "Actual size"
            item.image = NSImage(systemSymbolName: "1.magnifyingglass", accessibilityDescription: "Actual size")
            item.action = #selector(actualSize(_:))
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

private extension NSToolbarItem.Identifier {
    static let openDocument = NSToolbarItem.Identifier("macDVI.toolbar.open")
    static let zoomOut = NSToolbarItem.Identifier("macDVI.toolbar.zoomOut")
    static let actualSize = NSToolbarItem.Identifier("macDVI.toolbar.actualSize")
    static let zoomIn = NSToolbarItem.Identifier("macDVI.toolbar.zoomIn")
}
