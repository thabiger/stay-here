import AppKit
import Core
import Foundation

final class StatusBarController: NSObject, NSMenuDelegate, SpaceMenuRowViewCoordinating {
    private let item: NSStatusItem?
    private let menu = NSMenu()
    private let settings: SettingsRepository
    private let appearanceManager: AppearanceManager
    private var updateInfo: UpdateInfo?

    private var onOpenSettings: (() -> Void)?
    private var onOpenAbout: (() -> Void)?
    private var onCheckForUpdates: (() -> Void)?
    private var onOpenAvailableUpdate: (() -> Void)?
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

    init(settings: SettingsRepository, appearanceManager: AppearanceManager) {
        self.settings = settings
        self.appearanceManager = appearanceManager
        if !RuntimeEnvironment.isAutomationSession {
            self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        } else {
            self.item = nil
        }
        super.init()
    }

    var isEditingSpaceName: Bool {
        editingSpaceID != nil
    }

    var currentAppearance: NSAppearance? {
        appearanceManager.currentAppearance
    }

    func configure(
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onOpenAvailableUpdate: @escaping () -> Void,
        onCopyState: @escaping () -> Void,
        onOpenLogs: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onSelectSpace: @escaping (Int) -> Void,
        onRenameSpace: @escaping (Int, String) -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenAvailableUpdate = onOpenAvailableUpdate
        self.onCopyState = onCopyState
        self.onOpenLogs = onOpenLogs
        self.onQuit = onQuit
        self.onSelectSpace = onSelectSpace
        self.onRenameSpace = onRenameSpace

        setTitle(title)
        menu.delegate = self
        item?.menu = menu
        applyAppearance()

        rebuildMenu()
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
        rebuildMenu()
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        self.updateInfo = updateInfo
        rebuildMenu()
    }

    func selectSpace(_ spaceID: Int) {
        guard !isEditingSpaceName else { return }
        guard registry?.isSwitchableSpace(spaceID) == true else { return }
        // Defer until menu tracking ends; Ctrl+N shortcuts are ignored while the menu is open.
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onSelectSpace?(spaceID)
        }
    }

    func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool {
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

    func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool) {
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

    func commitActiveEdit() {
        editingRow?.commitEditFromController()
    }

    @objc private func openSettings() {
        guard !isEditingSpaceName else { return }
        onOpenSettings?()
    }

    @objc private func openAbout() {
        guard !isEditingSpaceName else { return }
        onOpenAbout?()
    }

    @objc private func checkForUpdates() {
        guard !isEditingSpaceName else { return }
        performAfterMenuCloses { [weak self] in
            self?.onCheckForUpdates?()
        }
    }

    @objc private func openAvailableUpdate() {
        guard !isEditingSpaceName else { return }
        performAfterMenuCloses { [weak self] in
            self?.onOpenAvailableUpdate?()
        }
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
        let appearance = appearanceManager.currentAppearance
        menu.appearance = appearance
        for item in menu.items {
            item.view?.appearance = appearance
            (item.view as? SpaceMenuRowView)?.applyAppearance(appearance)
            item.submenu?.appearance = appearance
        }
        item?.button?.appearance = appearance
        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let button = item?.button else { return }
        if settings.appearanceMode == .light {
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

    private func performAfterMenuCloses(_ action: @escaping () -> Void) {
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: action)
    }

    private func rebuildMenu() {
        guard !isEditingSpaceName else { return }
        menu.removeAllItems()

        if let registry {
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
                menu.addItem(.separator())
            }
        }

        if updateInfo != nil {
            menu.addItem(NSMenuItem(title: "Update Available…", action: #selector(openAvailableUpdate), keyEquivalent: "").withTarget(self))
        }
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").withTarget(self))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",").withTarget(self))
        menu.addItem(NSMenuItem(title: "About StayHere", action: #selector(openAbout), keyEquivalent: "").withTarget(self))

        if settings.diagnosticsEnabled {
            let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            let debugMenu = NSMenu()
            debugMenu.addItem(NSMenuItem(title: "Copy space state", action: #selector(copyState), keyEquivalent: "").withTarget(self))
            debugMenu.addItem(NSMenuItem(title: "Open logs", action: #selector(openLogs), keyEquivalent: "").withTarget(self))
            debug.submenu = debugMenu
            menu.addItem(debug)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StayHere", action: #selector(quit), keyEquivalent: "q").withTarget(self))
        applyAppearance()
    }

    #if DEBUG
    var debugMenuItemTitles: [String] {
        menu.items.map(\.title)
    }
    #endif
}

private extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
