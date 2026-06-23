import AppKit
import Core
import Foundation

@MainActor
protocol SpaceMenuRowViewCoordinating: AnyObject {
    var isEditingSpaceName: Bool { get }
    var currentAppearance: NSAppearance? { get }

    func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool
    func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool)
    func selectSpace(_ spaceID: Int)
    func commitActiveEdit()
}

final class SpaceMenuRowView: NSView, NSTextFieldDelegate {
    private enum Metrics {
        static let width: CGFloat = 280
        static let height: CGFloat = 28
        static let labelWidth: CGFloat = 82
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 4
    }

    private enum Timing {
        // Intentional inactivity timeout: commit edits after 5s with no typing.
        static let autoCommitInterval: TimeInterval = 5.0
        // Temporary workaround for menu-hosted editing focus loss; poll every 100ms.
        static let focusRepairInterval: TimeInterval = 0.1
    }

    private let spaceID: Int
    private weak var coordinator: SpaceMenuRowViewCoordinating?
    private let namespaceField = NSTextField(labelWithString: "")
    private let nameField = NSTextField(labelWithString: "")
    private let editor = NSTextField(string: "")
    private var isEditingName = false
    private var isHighlighted = false
    private var isFinishingEdit = false
    private var autoCommitTimer: Timer?
    private var focusRepairTimer: Timer?
    private var trackingArea: NSTrackingArea?

    init(spaceID: Int, namespaceLabel: String, name: String, controller: SpaceMenuRowViewCoordinating) {
        self.spaceID = spaceID
        self.coordinator = controller
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
        applyAppearance(self.coordinator?.currentAppearance)
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
        guard !isEditingName, coordinator?.isEditingSpaceName != true else { return }
        isHighlighted = true
        nameField.textColor = .selectedMenuItemTextColor
        namespaceField.textColor = .selectedMenuItemTextColor
        needsDisplay = true
    }

    func applyAppearance(_ appearance: NSAppearance?) {
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
        if coordinator?.isEditingSpaceName == true {
            coordinator?.commitActiveEdit()
            return
        }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control) else {
            coordinator?.selectSpace(spaceID)
            return
        }
        startEditing()
    }

    override func rightMouseDown(with event: NSEvent) {
        startEditing()
    }

    func commitEditFromController() {
        finishEditing(commit: true)
    }

    func resetVisualState() {
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

    private func startEditing() {
        guard !isEditingName else { return }
        guard coordinator?.beginEditing(row: self, spaceID: spaceID) == true else {
            finishEditing(commit: false)
            return
        }
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
        stopAutoCommit()
        guard isEditingName else { return }
        stopFocusRepair()
        isFinishingEdit = true
        isEditingName = false
        let value = editor.stringValue
        nameField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? SpaceDisplayNameProvider.defaultUnnamedName : value
        editor.isHidden = true
        nameField.isHidden = false
        resetVisualState()
        window?.makeFirstResponder(nil)
        isFinishingEdit = false
        coordinator?.finishEditing(row: self, spaceID: spaceID, name: value, commit: commit)
    }

    private func scheduleAutoCommit() {
        stopAutoCommit()
        let timer = Timer(timeInterval: Timing.autoCommitInterval, repeats: false) { [weak self] _ in
            self?.finishEditing(commit: true)
        }
        autoCommitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAutoCommit() {
        autoCommitTimer?.invalidate()
        autoCommitTimer = nil
    }

    private func startFocusRepair() {
        stopFocusRepair()
        let timer = Timer(timeInterval: Timing.focusRepairInterval, repeats: true) { [weak self] _ in
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
        stopAutoCommit()
        stopFocusRepair()
    }
}

extension SpaceMenuRowView {
    var isEditingForTesting: Bool {
        isEditingName
    }

    var displayedNameForTesting: String {
        nameField.stringValue
    }

    var isNameFieldHiddenForTesting: Bool {
        nameField.isHidden
    }

    var isEditorHiddenForTesting: Bool {
        editor.isHidden
    }

    var autoCommitTimerForTesting: Timer? {
        autoCommitTimer
    }

    var focusRepairTimerForTesting: Timer? {
        focusRepairTimer
    }

    func beginEditingForTesting() {
        startEditing()
    }

    func finishEditingForTesting(commit: Bool) {
        finishEditing(commit: commit)
    }

    func setEditorTextForTesting(_ text: String) {
        editor.stringValue = text
    }
}
