import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    // General Controls
    private let pageViewPopup = NSPopUpButton()
    private let autoScalesCheckbox = NSButton(checkboxWithTitle: "Auto-scale documents to window width", target: nil, action: nil)
    private let rememberPageCheckbox = NSButton(checkboxWithTitle: "Remember last viewed page per document", target: nil, action: nil)
    private let clearHistoryButton = NSButton(title: "Clear Reading History…", target: nil, action: nil)

    // SyncTeX Controls
    private let editorPopup = NSPopUpButton()
    private let customEditorField = NSTextField()
    private let customEditorLabel = NSTextField(labelWithString: "Command:")
    private let customEditorHelp = NSTextField(labelWithString: "Tokens: %file (file path), %line (line number), %col (column number)")
    private let highlightColorPopup = NSPopUpButton()
    private let highlightDurationPopup = NSPopUpButton()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        super.init(window: window)
        setupViews()
        loadSettings()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        loadSettings()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupViews() {
        guard let window, let contentView = window.contentView else { return }

        let tabView = NSTabView(frame: NSRect(x: 16, y: 16, width: 448, height: 308))
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // Tab 1: General
        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        let generalView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 260))
        generalView.autoresizingMask = [.width, .height]
        buildGeneralTab(in: generalView)
        generalItem.view = generalView
        tabView.addTabViewItem(generalItem)

        // Tab 2: SyncTeX
        let synctexItem = NSTabViewItem(identifier: "synctex")
        synctexItem.label = "SyncTeX"
        let synctexView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 260))
        synctexView.autoresizingMask = [.width, .height]
        buildSyncTeXTab(in: synctexView)
        synctexItem.view = synctexView
        tabView.addTabViewItem(synctexItem)

        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func buildGeneralTab(in container: NSView) {
        let pageViewLabel = NSTextField(labelWithString: "Default Page View:")
        pageViewLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pageViewLabel.translatesAutoresizingMaskIntoConstraints = false

        pageViewPopup.translatesAutoresizingMaskIntoConstraints = false
        pageViewPopup.addItems(withTitles: ["Single Page", "Two Pages"])
        pageViewPopup.target = self
        pageViewPopup.action = #selector(pageViewChanged(_:))

        autoScalesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        autoScalesCheckbox.target = self
        autoScalesCheckbox.action = #selector(autoScalesToggled(_:))

        rememberPageCheckbox.translatesAutoresizingMaskIntoConstraints = false
        rememberPageCheckbox.target = self
        rememberPageCheckbox.action = #selector(rememberPageToggled(_:))

        clearHistoryButton.translatesAutoresizingMaskIntoConstraints = false
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(clearHistoryClicked(_:))

        container.addSubview(pageViewLabel)
        container.addSubview(pageViewPopup)
        container.addSubview(autoScalesCheckbox)
        container.addSubview(rememberPageCheckbox)
        container.addSubview(clearHistoryButton)

        NSLayoutConstraint.activate([
            pageViewLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            pageViewLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            pageViewPopup.centerYAnchor.constraint(equalTo: pageViewLabel.centerYAnchor),
            pageViewPopup.leadingAnchor.constraint(equalTo: pageViewLabel.trailingAnchor, constant: 12),
            pageViewPopup.widthAnchor.constraint(equalToConstant: 160),

            autoScalesCheckbox.topAnchor.constraint(equalTo: pageViewLabel.bottomAnchor, constant: 20),
            autoScalesCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            autoScalesCheckbox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            rememberPageCheckbox.topAnchor.constraint(equalTo: autoScalesCheckbox.bottomAnchor, constant: 16),
            rememberPageCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            rememberPageCheckbox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            clearHistoryButton.topAnchor.constraint(equalTo: rememberPageCheckbox.bottomAnchor, constant: 24),
            clearHistoryButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20)
        ])
    }

    private func buildSyncTeXTab(in container: NSView) {
        let editorLabel = NSTextField(labelWithString: "Preferred TeX Editor:")
        editorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        editorLabel.translatesAutoresizingMaskIntoConstraints = false

        editorPopup.translatesAutoresizingMaskIntoConstraints = false
        editorPopup.removeAllItems()
        for choice in TeXEditorChoice.allCases {
            editorPopup.addItem(withTitle: choice.rawValue)
        }
        editorPopup.target = self
        editorPopup.action = #selector(editorChanged(_:))

        customEditorLabel.translatesAutoresizingMaskIntoConstraints = false
        customEditorField.translatesAutoresizingMaskIntoConstraints = false
        customEditorField.placeholderString = "code -g %file:%line:%col"
        customEditorField.target = self
        customEditorField.action = #selector(customEditorCommandChanged(_:))

        customEditorHelp.translatesAutoresizingMaskIntoConstraints = false
        customEditorHelp.font = .systemFont(ofSize: 11)
        customEditorHelp.textColor = .secondaryLabelColor

        let colorLabel = NSTextField(labelWithString: "Highlight Color:")
        colorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        colorLabel.translatesAutoresizingMaskIntoConstraints = false

        highlightColorPopup.translatesAutoresizingMaskIntoConstraints = false
        highlightColorPopup.removeAllItems()
        for color in SyncTeXHighlightColor.allCases {
            highlightColorPopup.addItem(withTitle: color.rawValue)
        }
        highlightColorPopup.target = self
        highlightColorPopup.action = #selector(highlightColorChanged(_:))

        let durationLabel = NSTextField(labelWithString: "Highlight Duration:")
        durationLabel.font = .systemFont(ofSize: 13, weight: .medium)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        highlightDurationPopup.translatesAutoresizingMaskIntoConstraints = false
        highlightDurationPopup.removeAllItems()
        highlightDurationPopup.addItems(withTitles: ["1 Second", "2 Seconds", "3 Seconds", "5 Seconds"])
        highlightDurationPopup.target = self
        highlightDurationPopup.action = #selector(highlightDurationChanged(_:))

        container.addSubview(editorLabel)
        container.addSubview(editorPopup)
        container.addSubview(customEditorLabel)
        container.addSubview(customEditorField)
        container.addSubview(customEditorHelp)
        container.addSubview(colorLabel)
        container.addSubview(highlightColorPopup)
        container.addSubview(durationLabel)
        container.addSubview(highlightDurationPopup)

        NSLayoutConstraint.activate([
            editorLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            editorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            editorPopup.centerYAnchor.constraint(equalTo: editorLabel.centerYAnchor),
            editorPopup.leadingAnchor.constraint(equalTo: editorLabel.trailingAnchor, constant: 12),
            editorPopup.widthAnchor.constraint(equalToConstant: 180),

            customEditorLabel.topAnchor.constraint(equalTo: editorLabel.bottomAnchor, constant: 14),
            customEditorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            customEditorField.centerYAnchor.constraint(equalTo: customEditorLabel.centerYAnchor),
            customEditorField.leadingAnchor.constraint(equalTo: customEditorLabel.trailingAnchor, constant: 12),
            customEditorField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            customEditorHelp.topAnchor.constraint(equalTo: customEditorField.bottomAnchor, constant: 4),
            customEditorHelp.leadingAnchor.constraint(equalTo: customEditorField.leadingAnchor),
            customEditorHelp.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            colorLabel.topAnchor.constraint(equalTo: customEditorHelp.bottomAnchor, constant: 16),
            colorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            highlightColorPopup.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor),
            highlightColorPopup.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 12),
            highlightColorPopup.widthAnchor.constraint(equalToConstant: 140),

            durationLabel.topAnchor.constraint(equalTo: colorLabel.bottomAnchor, constant: 16),
            durationLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            highlightDurationPopup.centerYAnchor.constraint(equalTo: durationLabel.centerYAnchor),
            highlightDurationPopup.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 12),
            highlightDurationPopup.widthAnchor.constraint(equalToConstant: 140)
        ])
    }

    func loadSettings() {
        let settings = AppSettings.shared

        pageViewPopup.selectItem(at: settings.isTwoPageViewEnabled ? 1 : 0)
        autoScalesCheckbox.state = settings.isAutoScalesEnabled ? .on : .off
        rememberPageCheckbox.state = settings.isRememberPageEnabled ? .on : .off

        editorPopup.selectItem(withTitle: settings.selectedEditor.rawValue)
        customEditorField.stringValue = settings.customEditorCommand
        updateCustomEditorVisibility()

        highlightColorPopup.selectItem(withTitle: settings.highlightColor.rawValue)

        let duration = settings.highlightDuration
        if duration <= 1.0 {
            highlightDurationPopup.selectItem(at: 0)
        } else if duration <= 2.0 {
            highlightDurationPopup.selectItem(at: 1)
        } else if duration <= 3.0 {
            highlightDurationPopup.selectItem(at: 2)
        } else {
            highlightDurationPopup.selectItem(at: 3)
        }
    }

    private func updateCustomEditorVisibility() {
        let isCustom = (editorPopup.titleOfSelectedItem == TeXEditorChoice.custom.rawValue)
        customEditorField.isEnabled = isCustom
        customEditorLabel.textColor = isCustom ? .labelColor : .disabledControlTextColor
        customEditorHelp.textColor = isCustom ? .secondaryLabelColor : .disabledControlTextColor
    }

    // MARK: - Actions

    @objc private func pageViewChanged(_ sender: NSPopUpButton) {
        AppSettings.shared.isTwoPageViewEnabled = (sender.indexOfSelectedItem == 1)
    }

    @objc private func autoScalesToggled(_ sender: NSButton) {
        AppSettings.shared.isAutoScalesEnabled = (sender.state == .on)
    }

    @objc private func rememberPageToggled(_ sender: NSButton) {
        AppSettings.shared.isRememberPageEnabled = (sender.state == .on)
    }

    @objc private func clearHistoryClicked(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Clear Reading History"
        alert.informativeText = "Are you sure you want to clear the saved page positions for all documents?"
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            DocumentHistoryStore.clearHistory()
        }
    }

    @objc private func editorChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem, let choice = TeXEditorChoice(rawValue: title) {
            AppSettings.shared.selectedEditor = choice
        }
        updateCustomEditorVisibility()
    }

    @objc private func customEditorCommandChanged(_ sender: NSTextField) {
        AppSettings.shared.customEditorCommand = sender.stringValue.trimmingCharacters(in: .whitespaces)
    }

    @objc private func highlightColorChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem, let color = SyncTeXHighlightColor(rawValue: title) {
            AppSettings.shared.highlightColor = color
        }
    }

    @objc private func highlightDurationChanged(_ sender: NSPopUpButton) {
        let durations = [1.0, 2.0, 3.0, 5.0]
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < durations.count {
            AppSettings.shared.highlightDuration = durations[idx]
        }
    }
}
