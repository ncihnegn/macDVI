import Foundation

enum DocumentHistoryStore {
    private static let userDefaultsKey = "macDVI.lastViewedPagePerFile"

    /// Key for identifying a file in persistent storage.
    /// Uses standardized file URL path (resolving symlinks if applicable).
    private static func storageKey(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Retrieves the 0-based page index last viewed for the given file URL.
    static func lastViewedPage(for url: URL) -> Int? {
        let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Int] ?? [:]
        return dict[storageKey(for: url)]
    }

    /// Records the 0-based page index for the given file URL.
    static func setLastViewedPage(_ pageIndex: Int, for url: URL) {
        var dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Int] ?? [:]
        dict[storageKey(for: url)] = pageIndex
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
    }
}
