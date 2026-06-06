import AppKit
import Core
import Foundation

final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var onOpenSettings: (() -> Void)?
    private var onCopyState: (() -> Void)?
    private var onOpenLogs: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var onSelectSpace: ((Int) -> Void)?
    private var onRenameSpace: ((Int, String) -> Void)?
    private weak var registry: SpaceRegistry?
    private weak var editingRow: SpaceMenuRowView?
    private var editingSpaceID: Int?
    private var suppressNextEditRebuild = false
    private var title = "Unnamed space"

    var isEditingSpaceName: Bool {
        editingSpaceID != nil
    }

    func configure(
        onOpenSettings: @escaping () -> Void,
        onCopyState: @escaping () -> Void,
        onOpenLogs: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onSelectSpace: @escaping (Int) -> Void,
        onRenameSpace: @escaping (Int, String) -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onCopyState = onCopyState
        self.onOpenLogs = onOpenLogs
        self.onQuit = onQuit
        self.onSelectSpace = onSelectSpace
        self.onRenameSpace = onRenameSpace

        setTitle(title)
        menu.delegate = self
        item.menu = menu
        applyAppearance()

        rebuildBaseMenu()
    }

    func setTitle(_ text: String) {
        title = text
        updateStatusItemTitle()
    }

    func applyCurrentAppearance() {
        applyAppearance()
    }

    func rebuildSpaceItems(registry: SpaceRegistry) {
        guard !isEditingSpaceName else { return }
        self.registry = registry
        menu.removeAllItems()
        let spaceIDs = registry.switchableOrderedSpaceIDs()
        for id in spaceIDs {
            let row = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            row.representedObject = NSNumber(value: id)
            row.isEnabled = registry.isSwitchableSpace(id)
            row.view = SpaceMenuRowView(
                spaceID: id,
                namespaceLabel: registry.namespaceLabel(for: id),
                name: registry.displayName(for: id),
                controller: self
            )
            menu.addItem(row)
        }

        if !spaceIDs.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",").withTarget(self))

        let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        debugMenu.addItem(NSMenuItem(title: "Copy space state", action: #selector(copyState), keyEquivalent: "").withTarget(self))
        debugMenu.addItem(NSMenuItem(title: "Open logs", action: #selector(openLogs), keyEquivalent: "").withTarget(self))
        debug.submenu = debugMenu
        menu.addItem(debug)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StayHere", action: #selector(quit), keyEquivalent: "q").withTarget(self))
        applyAppearance()
    }

    private func rebuildBaseMenu() {
        menu.removeAllItems()
        applyAppearance()
    }

    fileprivate func selectSpace(_ spaceID: Int) {
        guard !isEditingSpaceName else { return }
        guard registry?.isSwitchableSpace(spaceID) == true else { return }
        // Defer until menu tracking ends; Ctrl+N shortcuts are ignored while the menu is open.
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onSelectSpace?(spaceID)
        }
    }

    fileprivate func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool {
        if let editingSpaceID, editingSpaceID != spaceID {
            suppressNextEditRebuild = true
            editingRow?.commitEditFromController()
        }
        guard editingSpaceID == nil || editingSpaceID == spaceID else { return false }
        editingSpaceID = spaceID
        editingRow = row
        setMenuItemsEnabledForEditing(activeSpaceID: spaceID)
        return true
    }

    fileprivate func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool) {
        guard editingSpaceID == spaceID, editingRow === row else { return }
        let shouldRebuild = !suppressNextEditRebuild
        suppressNextEditRebuild = false
        editingSpaceID = nil
        editingRow = nil
        setAllMenuItemsEnabled(true)
        if commit {
            onRenameSpace?(spaceID, name)
        }
        if shouldRebuild, let registry {
            rebuildSpaceItems(registry: registry)
        }
    }

    fileprivate func commitActiveEdit() {
        editingRow?.commitEditFromController()
    }

    @objc private func openSettings() {
        guard !isEditingSpaceName else { return }
        onOpenSettings?()
    }

    @objc private func copyState() {
        guard !isEditingSpaceName else { return }
        onCopyState?()
    }

    @objc private func openLogs() {
        guard !isEditingSpaceName else { return }
        onOpenLogs?()
    }

    @objc private func quit() {
        guard !isEditingSpaceName else { return }
        onQuit?()
    }

    func menuWillOpen(_ menu: NSMenu) {
        applyAppearance()
        resetSpaceRowVisualState()
    }

    func menuDidClose(_ menu: NSMenu) {
        resetSpaceRowVisualState()
    }

    private func setMenuItemsEnabledForEditing(activeSpaceID: Int) {
        for item in menu.items {
            item.isEnabled = item.representedObject is NSNumber
        }
    }

    private func setAllMenuItemsEnabled(_ enabled: Bool) {
        for item in menu.items {
            item.isEnabled = enabled
        }
    }

    private func resetSpaceRowVisualState() {
        for item in menu.items {
            (item.view as? SpaceMenuRowView)?.resetVisualState()
        }
    }

    private func applyAppearance() {
        let appearance = AppearanceManager.currentAppearance
        menu.appearance = appearance
        for item in menu.items {
            item.view?.appearance = appearance
            (item.view as? SpaceMenuRowView)?.applyAppearance(appearance)
            item.submenu?.appearance = appearance
        }
        item.button?.appearance = appearance
        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let button = item.button else { return }
        if AppearanceSettings.shared.mode == .light {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.menuBarFont(ofSize: 0)
                ]
            )
        } else {
            button.title = title
        }
    }
}

private extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}

private final class SpaceMenuRowView: NSView, NSTextFieldDelegate {
    private enum Metrics {
        static let width: CGFloat = 280
        static let height: CGFloat = 28
        static let labelWidth: CGFloat = 82
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 4
    }

    private let spaceID: Int
    private weak var controller: StatusBarController?
    private let namespaceField = NSTextField(labelWithString: "")
    private let nameField = NSTextField(labelWithString: "")
    private let editor = NSTextField(string: "")
    private var isEditingName = false
    private var isHighlighted = false
    private var isFinishingEdit = false
    private var autoCommitTimer: Timer?
    private var focusRepairTimer: Timer?
    private var trackingArea: NSTrackingArea?

    init(spaceID: Int, namespaceLabel: String, name: String, controller: StatusBarController) {
        self.spaceID = spaceID
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height))

        namespaceField.stringValue = namespaceLabel
        namespaceField.textColor = .secondaryLabelColor
        namespaceField.font = .menuFont(ofSize: NSFont.systemFontSize)
        namespaceField.lineBreakMode = .byTruncatingTail

        nameField.stringValue = name
        nameField.font = .menuFont(ofSize: NSFont.systemFontSize)
        nameField.lineBreakMode = .byTruncatingTail

        editor.stringValue = name
        editor.font = .menuFont(ofSize: NSFont.systemFontSize)
        editor.isBordered = true
        editor.isBezeled = true
        editor.bezelStyle = .roundedBezel
        editor.delegate = self
        editor.isHidden = true

        addSubview(namespaceField)
        addSubview(nameField)
        addSubview(editor)
        applyAppearance(AppearanceManager.currentAppearance)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let labelX = Metrics.horizontalPadding
        let nameX = labelX + Metrics.labelWidth + 8
        let rowHeight = bounds.height - Metrics.verticalPadding * 2
        namespaceField.frame = NSRect(
            x: labelX,
            y: Metrics.verticalPadding,
            width: Metrics.labelWidth,
            height: rowHeight
        )
        nameField.frame = NSRect(
            x: nameX,
            y: Metrics.verticalPadding,
            width: bounds.width - nameX - Metrics.horizontalPadding,
            height: rowHeight
        )
        editor.frame = nameField.frame.insetBy(dx: -3, dy: 0)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        if isEditingName {
            keepEditorFocused()
            return
        }
        guard !isEditingName, controller?.isEditingSpaceName != true else { return }
        isHighlighted = true
        nameField.textColor = .selectedMenuItemTextColor
        namespaceField.textColor = .selectedMenuItemTextColor
        needsDisplay = true
    }

    fileprivate func applyAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        namespaceField.appearance = appearance
        nameField.appearance = appearance
        editor.appearance = appearance
        resetVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        if isEditingName {
            keepEditorFocused()
            return
        }
        isHighlighted = false
        nameField.textColor = .labelColor
        namespaceField.textColor = .secondaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isEditingName, isHighlighted else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {
        if controller?.isEditingSpaceName == true {
            controller?.commitActiveEdit()
            return
        }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control) else {
            controller?.selectSpace(spaceID)
            return
        }
        startEditing()
    }

    override func rightMouseDown(with event: NSEvent) {
        startEditing()
    }

    private func startEditing() {
        guard !isEditingName, controller?.beginEditing(row: self, spaceID: spaceID) == true else { return }
        isEditingName = true
        isHighlighted = false
        namespaceField.textColor = .labelColor
        nameField.isHidden = true
        editor.isHidden = false
        editor.stringValue = nameField.stringValue
        needsDisplay = true
        window?.makeFirstResponder(editor)
        editor.currentEditor()?.selectAll(nil)
        startFocusRepair()
        scheduleAutoCommit()
    }

    private func finishEditing(commit: Bool) {
        autoCommitTimer?.invalidate()
        autoCommitTimer = nil
        guard isEditingName else { return }
        stopFocusRepair()
        isFinishingEdit = true
        isEditingName = false
        let value = editor.stringValue
        nameField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed space" : value
        editor.isHidden = true
        nameField.isHidden = false
        resetVisualState()
        window?.makeFirstResponder(nil)
        isFinishingEdit = false
        controller?.finishEditing(row: self, spaceID: spaceID, name: value, commit: commit)
    }

    fileprivate func commitEditFromController() {
        finishEditing(commit: true)
    }

    fileprivate func resetVisualState() {
        guard !isEditingName else {
            isHighlighted = false
            namespaceField.textColor = .labelColor
            needsDisplay = true
            return
        }
        isHighlighted = false
        nameField.textColor = .labelColor
        namespaceField.textColor = .secondaryLabelColor
        needsDisplay = true
    }

    private func scheduleAutoCommit() {
        autoCommitTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.finishEditing(commit: true)
        }
        autoCommitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startFocusRepair() {
        stopFocusRepair()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.keepEditorFocused()
        }
        focusRepairTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopFocusRepair() {
        focusRepairTimer?.invalidate()
        focusRepairTimer = nil
    }

    private func keepEditorFocused() {
        guard isEditingName, !isFinishingEdit, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, self.isEditingName, !self.isFinishingEdit, let window else { return }
            let firstResponder = window.firstResponder
            if firstResponder === self.editor { return }
            if let fieldEditor = self.editor.currentEditor(), firstResponder === fieldEditor { return }
            window.makeFirstResponder(self.editor)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleAutoCommit()
    }

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishEditing(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishEditing(commit: false)
            return true
        default:
            return false
        }
    }

    deinit {
        autoCommitTimer?.invalidate()
        stopFocusRepair()
    }
}
