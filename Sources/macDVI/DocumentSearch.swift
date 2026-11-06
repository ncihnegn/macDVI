import AppKit
import Foundation
import PDFKit

// MARK: - DVI Search Engine

struct DVISearchMatch: Equatable {
    let matchIndex: Int
    let pageIndex: Int
    let range: NSRange
    let text: String
    let rects: [CGRect] // Bounding box(es) in unscaled DVI points on that page
}

struct DVIPageTextInfo {
    let text: String
    let charRects: [CGRect?] // Corresponding bounding box for each character in text, or nil for \n
}

final class DVISearchEngine {
    private var pageCache: [Int: DVIPageTextInfo] = [:]
    private var cachedDocumentURL: URL?

    func clearCache() {
        pageCache.removeAll()
        cachedDocumentURL = nil
    }

    func pageTextInfo(for pageIndex: Int, in document: DVIDocument) -> DVIPageTextInfo {
        if cachedDocumentURL != document.url {
            pageCache.removeAll()
            cachedDocumentURL = document.url
        }

        if let cached = pageCache[pageIndex] {
            return cached
        }

        guard pageIndex >= 0 && pageIndex < document.pages.count else {
            let empty = DVIPageTextInfo(text: "", charRects: [])
            return empty
        }

        let info = extractText(from: document.pages[pageIndex], document: document)
        pageCache[pageIndex] = info
        return info
    }

    func search(document: DVIDocument, query: String, caseSensitive: Bool) -> [DVISearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var allMatches: [DVISearchMatch] = []
        var matchCounter = 0

        var options: NSString.CompareOptions = [.literal]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        for pageIndex in 0..<document.pages.count {
            let info = pageTextInfo(for: pageIndex, in: document)
            let pageText = info.text
            guard !pageText.isEmpty else { continue }

            var searchRange = pageText.startIndex..<pageText.endIndex
            while searchRange.lowerBound < pageText.endIndex,
                  let foundRange = pageText.range(of: query, options: options, range: searchRange) {

                let utf16Start = pageText.distance(from: pageText.startIndex, to: foundRange.lowerBound)
                let utf16Length = pageText.distance(from: foundRange.lowerBound, to: foundRange.upperBound)
                let nsRange = NSRange(location: utf16Start, length: utf16Length)

                // Gather character rects
                var rawRects: [CGRect] = []
                let charStartIndex = pageText.distance(from: pageText.startIndex, to: foundRange.lowerBound)
                let charEndIndex = pageText.distance(from: pageText.startIndex, to: foundRange.upperBound)

                for idx in charStartIndex..<min(charEndIndex, info.charRects.count) {
                    if let r = info.charRects[idx] {
                        rawRects.append(r)
                    }
                }

                let merged = mergeRects(rawRects)
                let match = DVISearchMatch(
                    matchIndex: matchCounter,
                    pageIndex: pageIndex,
                    range: nsRange,
                    text: String(pageText[foundRange]),
                    rects: merged
                )
                allMatches.append(match)
                matchCounter += 1

                if foundRange.upperBound == pageText.endIndex {
                    break
                }
                searchRange = foundRange.upperBound..<pageText.endIndex
            }
        }

        return allMatches
    }

    private func extractText(from page: DVIPage, document: DVIDocument) -> DVIPageTextInfo {
        var glyphs: [DVIGlyph] = []
        for item in page.items {
            if case .glyph(let g) = item {
                glyphs.append(g)
            }
        }

        guard !glyphs.isEmpty else {
            return DVIPageTextInfo(text: "", charRects: [])
        }

        // Sort glyphs in visual reading order: line by line, left to right
        glyphs.sort { g1, g2 in
            let diff = g1.baselineY - g2.baselineY
            let threshold = max(min(g1.fontSize, g2.fontSize) * 0.4, 3.5)
            if abs(diff) > threshold {
                return g1.baselineY < g2.baselineY
            }
            return g1.x < g2.x
        }

        var characters: [Character] = []
        var rects: [CGRect?] = []

        var lastGlyph: DVIGlyph? = nil

        for g in glyphs {
            let fontName = document.fonts[g.fontNumber]?.name ?? ""
            let glyphString = TeXGlyphMapper.string(for: g.characterCode, fontName: fontName)
            guard !glyphString.isEmpty else { continue }

            let ascender = max(g.height, g.fontSize * 0.75)
            let descender = max(g.depth, g.fontSize * 0.25)
            let boxY = g.baselineY - ascender
            let boxHeight = ascender + descender
            let boxWidth = max(g.advance, g.fontSize * 0.25)
            let glyphRect = CGRect(x: g.x, y: boxY, width: boxWidth, height: boxHeight)

            if let last = lastGlyph {
                let baselineDiff = abs(g.baselineY - last.baselineY)
                let lineThreshold = max(min(g.fontSize, last.fontSize) * 0.4, 3.5)

                if baselineDiff > lineThreshold {
                    // New line
                    characters.append("\n")
                    rects.append(nil)
                } else {
                    // Same line: check horizontal gap for inter-word space
                    let gap = g.x - (last.x + last.advance)
                    let spaceThreshold = max(min(last.fontSize, g.fontSize) * 0.15, 1.8)
                    if gap >= spaceThreshold {
                        characters.append(" ")
                        let spaceBox = CGRect(
                            x: last.x + last.advance,
                            y: boxY,
                            width: max(gap, 2.0),
                            height: boxHeight
                        )
                        rects.append(spaceBox)
                    }
                }
            }

            if glyphString.count == 1 {
                characters.append(glyphString.first!)
                rects.append(glyphRect)
            } else {
                // Multi-character ligature (e.g. "fi", "fl", "ffi")
                let pieceWidth = boxWidth / Double(glyphString.count)
                for (offset, char) in glyphString.enumerated() {
                    characters.append(char)
                    let pieceRect = CGRect(
                        x: g.x + Double(offset) * pieceWidth,
                        y: boxY,
                        width: pieceWidth,
                        height: boxHeight
                    )
                    rects.append(pieceRect)
                }
            }

            lastGlyph = g
        }

        return DVIPageTextInfo(
            text: String(characters),
            charRects: rects
        )
    }

    private func mergeRects(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }

        var merged: [CGRect] = []
        var current: CGRect = rects[0]

        for i in 1..<rects.count {
            let next = rects[i]

            // Check if next rect is on the same line and roughly adjacent
            let sameLine = abs(next.midY - current.midY) < max(next.height, current.height) * 0.4
            let adjacent = next.minX >= current.minX - 2.0 && next.minX <= current.maxX + max(next.height * 0.6, 6.0)

            if sameLine && adjacent {
                current = current.union(next)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }
}

// MARK: - Find Bar View

final class FindBarView: NSView, NSSearchFieldDelegate {
    private let visualEffectView = NSVisualEffectView()
    let searchField = NSSearchField()
    let countLabel = NSTextField(labelWithString: "")
    let segmentedNav = NSSegmentedControl()
    let matchCaseButton = NSButton()
    let doneButton = NSButton()

    var onSearchTextChanged: ((String) -> Void)?
    var onNextMatch: (() -> Void)?
    var onPreviousMatch: (() -> Void)?
    var onToggleMatchCase: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    var isCaseSensitive: Bool {
        matchCaseButton.state == .on
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .headerView
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .followsWindowActiveState
        addSubview(visualEffectView)

        let bottomBorder = NSBox()
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        bottomBorder.boxType = .separator
        addSubview(bottomBorder)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Find"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldValueChanged(_:))

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        segmentedNav.translatesAutoresizingMaskIntoConstraints = false
        segmentedNav.segmentCount = 2
        segmentedNav.setImage(NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous"), forSegment: 0)
        segmentedNav.setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next"), forSegment: 1)
        segmentedNav.setToolTip("Previous Match (⇧⌘G)", forSegment: 0)
        segmentedNav.setToolTip("Next Match (⌘G)", forSegment: 1)
        segmentedNav.trackingMode = .momentary
        segmentedNav.target = self
        segmentedNav.action = #selector(segmentClicked(_:))
        segmentedNav.setEnabled(false, forSegment: 0)
        segmentedNav.setEnabled(false, forSegment: 1)

        matchCaseButton.translatesAutoresizingMaskIntoConstraints = false
        matchCaseButton.setButtonType(.switch)
        matchCaseButton.title = "Match Case"
        matchCaseButton.font = .systemFont(ofSize: 11)
        matchCaseButton.controlSize = .small
        matchCaseButton.target = self
        matchCaseButton.action = #selector(matchCaseToggled(_:))

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.title = "Done"
        doneButton.bezelStyle = .roundRect
        doneButton.controlSize = .small
        doneButton.font = .systemFont(ofSize: 11, weight: .medium)
        doneButton.target = self
        doneButton.action = #selector(doneClicked(_:))

        let stack = NSStackView(views: [
            searchField,
            countLabel,
            segmentedNav,
            matchCaseButton,
            doneButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.setCustomSpacing(14, after: searchField)
        stack.setCustomSpacing(12, after: countLabel)
        stack.setCustomSpacing(12, after: segmentedNav)
        addSubview(stack)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        ])
    }

    func updateMatchStatus(currentIndex: Int, totalMatches: Int, hasQuery: Bool) {
        if !hasQuery {
            countLabel.stringValue = ""
            segmentedNav.setEnabled(false, forSegment: 0)
            segmentedNav.setEnabled(false, forSegment: 1)
        } else if totalMatches == 0 {
            countLabel.stringValue = "No results"
            segmentedNav.setEnabled(false, forSegment: 0)
            segmentedNav.setEnabled(false, forSegment: 1)
        } else {
            countLabel.stringValue = "\(currentIndex + 1) of \(totalMatches)"
            segmentedNav.setEnabled(true, forSegment: 0)
            segmentedNav.setEnabled(true, forSegment: 1)
        }
    }

    func makeSearchFieldFirstResponder() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func setQuery(_ text: String) {
        searchField.stringValue = text
        onSearchTextChanged?(text)
    }

    @objc private func searchFieldValueChanged(_ sender: NSSearchField) {
        onSearchTextChanged?(sender.stringValue)
    }

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            onPreviousMatch?()
        } else {
            onNextMatch?()
        }
    }

    @objc private func matchCaseToggled(_ sender: NSButton) {
        onToggleMatchCase?(sender.state == .on)
    }

    @objc private func doneClicked(_ sender: NSButton) {
        onClose?()
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        onSearchTextChanged?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPreviousMatch?()
            } else {
                onNextMatch?()
            }
            return true
        }
        return false
    }
}
