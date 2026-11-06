import AppKit
import Foundation

enum TeXEditorChoice: String, CaseIterable {
    case auto = "Auto-detect"
    case vscode = "VS Code"
    case cursor = "Cursor"
    case zed = "Zed"
    case sublime = "Sublime Text"
    case macvim = "MacVim"
    case bbedit = "BBEdit"
    case emacs = "Emacs"
    case custom = "Custom Command"
}

enum SyncTeXHighlightColor: String, CaseIterable {
    case blue = "Blue"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case purple = "Purple"

    var color: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .purple: return .systemPurple
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()

    enum Keys {
        static let twoPageView = "macDVI.twoPageViewEnabled"
        static let autoScales = "macDVI.autoScalesEnabled"
        static let rememberPage = "macDVI.rememberLastViewedPage"
        static let selectedEditor = "macDVI.selectedEditor"
        static let customEditorCommand = "macDVI.customEditorCommand"
        static let highlightColor = "macDVI.synctexHighlightColor"
        static let highlightDuration = "macDVI.synctexHighlightDuration"
    }

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.rememberPage: true,
            Keys.selectedEditor: TeXEditorChoice.auto.rawValue,
            Keys.customEditorCommand: "",
            Keys.highlightColor: SyncTeXHighlightColor.blue.rawValue,
            Keys.highlightDuration: 2.0
        ])
    }

    var isTwoPageViewEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.twoPageView) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.twoPageView)
            postChange()
        }
    }

    var isAutoScalesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoScales) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoScales)
            postChange()
        }
    }

    var isRememberPageEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.rememberPage) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.rememberPage)
            postChange()
        }
    }

    var selectedEditor: TeXEditorChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.selectedEditor) ?? ""
            return TeXEditorChoice(rawValue: raw) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.selectedEditor)
            postChange()
        }
    }

    var customEditorCommand: String {
        get { UserDefaults.standard.string(forKey: Keys.customEditorCommand) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.customEditorCommand)
            postChange()
        }
    }

    var highlightColor: SyncTeXHighlightColor {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.highlightColor) ?? ""
            return SyncTeXHighlightColor(rawValue: raw) ?? .blue
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.highlightColor)
            postChange()
        }
    }

    var highlightDuration: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: Keys.highlightDuration)
            return val > 0 ? val : 2.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.highlightDuration)
            postChange()
        }
    }

    private func postChange() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: self)
    }
}

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("macDVI.appSettingsDidChange")
}
