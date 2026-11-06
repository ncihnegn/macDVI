import Foundation

final class PageNavigationHistory {
    private(set) var entries: [Int] = []
    private(set) var currentIndex: Int = -1
    private let maxEntries: Int

    init(maxEntries: Int = 100) {
        self.maxEntries = maxEntries
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var canGoForward: Bool {
        currentIndex >= 0 && currentIndex < entries.count - 1
    }

    var currentPage: Int? {
        guard currentIndex >= 0 && currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    func clear() {
        entries.removeAll()
        currentIndex = -1
    }

    /// Records visiting a page.
    func record(pageNumber: Int) {
        guard pageNumber > 0 else { return }

        // If we are already at this page at currentIndex, don't create consecutive duplicates
        if currentIndex >= 0 && currentIndex < entries.count && entries[currentIndex] == pageNumber {
            return
        }

        // Truncate any forward history when branching off with a new navigation
        if currentIndex >= 0 && currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }

        entries.append(pageNumber)
        currentIndex = entries.count - 1

        if entries.count > maxEntries {
            let overflow = entries.count - maxEntries
            entries.removeFirst(overflow)
            currentIndex = entries.count - 1
        }
    }

    /// Moves backward in history and returns the target page number.
    func goBack() -> Int? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    /// Moves forward in history and returns the target page number.
    func goForward() -> Int? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }
}
