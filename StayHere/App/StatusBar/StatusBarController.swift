import AppKit
import Core
import Foundation

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, StatusBarMenuActionHandler, SpaceMenuProviding {
    private let item: NSStatusItem?
    private let menu = NSMenu()
    private let settings: AppearanceSettings & DiagnosticsSettings
    private let appearanceManager: AppearanceManager
    private let menuBuilder = StatusBarMenuBuilder()
    private let renameCoordinator: SpaceRenameCoordinator
    private let appearanceApplier: StatusBarAppearanceApplier
    private var updateInfo: UpdateInfo?
    private var snapshot: SpaceListSnapshot?

    private var actions: StatusBarActions?
    private var title = SpaceDisplayNameProvider.defaultUnnamedName

    var isEditingSpaceName: Bool {
        renameCoordinator.isEditingSpaceName
    }

    init(settings: AppearanceSettings & DiagnosticsSettings, appearanceManager: AppearanceManager) {
        self.settings = settings
        self.appearanceManager = appearanceManager
        self.renameCoordinator = SpaceRenameCoordinator(appearanceManager: appearanceManager)
        self.appearanceApplier = StatusBarAppearanceApplier(
            settings: settings,
            appearanceManager: appearanceManager
        )
        if !RuntimeEnvironment.isAutomationSession {
            self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        } else {
            self.item = nil
        }
        super.init()
    }

    func configure(registry: any SpaceRegistryProtocol, actions: StatusBarActions) {
        self.actions = actions

        renameCoordinator.configure(
            onRenameSpace: { [weak self] spaceID, name in
                self?.actions?.onRenameSpace(spaceID, name)
            }
        )
        renameCoordinator.setMenuProvider(self)

        setTitle(title)
        menu.delegate = self
        item?.menu = menu

        snapshot = SpaceListSnapshot.build(
            from: registry,
            updateInfo: updateInfo,
            diagnosticsEnabled: settings.diagnosticsEnabled
        )
        applyAppearance()
        rebuildMenu()
    }

    func setTitle(_ text: String) {
        title = text
        applyAppearance()
    }

    func applyCurrentAppearance() {
        applyAppearance()
    }

    func rebuildSpaceItems(registry: any SpaceRegistryProtocol) {
        guard !isEditingSpaceName else { return }
        snapshot = SpaceListSnapshot.build(
            from: registry,
            updateInfo: updateInfo,
            diagnosticsEnabled: settings.diagnosticsEnabled
        )
        rebuildMenu()
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        self.updateInfo = updateInfo
        if var snapshot {
            snapshot = SpaceListSnapshot(
                spaceItems: snapshot.spaceItems,
                updateInfo: updateInfo,
                diagnosticsEnabled: snapshot.diagnosticsEnabled
            )
            self.snapshot = snapshot
        }
        rebuildMenu()
    }

    func selectSpace(_ spaceID: Int) {
        renameCoordinator.selectSpace(spaceID)
    }

    func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool {
        renameCoordinator.beginEditing(row: row, spaceID: spaceID)
    }

    func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool) {
        renameCoordinator.finishEditing(row: row, spaceID: spaceID, name: name, commit: commit)
    }

    func commitActiveEdit() {
        renameCoordinator.commitActiveEdit()
    }

    @objc func openSettings() {
        guard !isEditingSpaceName else { return }
        actions?.onOpenSettings()
    }

    @objc func openAbout() {
        guard !isEditingSpaceName else { return }
        actions?.onOpenAbout()
    }

    @objc func checkForUpdates() {
        guard !isEditingSpaceName else { return }
        performAfterMenuCloses { [weak self] in
            self?.actions?.onCheckForUpdates()
        }
    }

    @objc func openAvailableUpdate() {
        guard !isEditingSpaceName else { return }
        performAfterMenuCloses { [weak self] in
            self?.actions?.onOpenAvailableUpdate()
        }
    }

    @objc func copyState() {
        guard !isEditingSpaceName else { return }
        actions?.onCopyState()
    }

    @objc func openLogs() {
        guard !isEditingSpaceName else { return }
        actions?.onOpenLogs()
    }

    @objc func quit() {
        guard !isEditingSpaceName else { return }
        actions?.onQuit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        applyAppearance()
        resetSpaceRowVisualState()
    }

    func menuDidClose(_ menu: NSMenu) {
        resetSpaceRowVisualState()
    }

    private func rebuildMenu() {
        guard !isEditingSpaceName else { return }
        menu.removeAllItems()

        guard let snapshot else {
            applyAppearance()
            return
        }

        let items = menuBuilder.buildMenuItems(
            from: snapshot,
            coordinator: renameCoordinator,
            target: self
        )
        items.forEach { menu.addItem($0) }
        applyAppearance()
    }

    func setMenuItemsEnabledForEditing(activeSpaceID: Int) {
        for item in menu.items {
            item.isEnabled = item.representedObject is NSNumber
        }
    }

    func setAllMenuItemsEnabled(_ enabled: Bool) {
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
        appearanceApplier.applyAppearance(
            to: menu,
            statusItemButton: item?.button,
            title: title
        )
    }

    private func performAfterMenuCloses(_ action: @escaping () -> Void) {
        menu.cancelTracking()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            action()
        }
    }

    func isSwitchableSpace(_ spaceID: Int) -> Bool {
        snapshot?.spaceItems.contains(where: { $0.spaceID == spaceID }) ?? false
    }

    private var isSelectingSpace = false

    func performSpaceSelection(_ spaceID: Int) {
        guard !isSelectingSpace else { return }
        isSelectingSpace = true
        menu.cancelTracking()
        actions?.onSelectSpace(spaceID)
        isSelectingSpace = false
    }

    func updateSpaceName(spaceID: Int, name: String) {
        guard var snapshot else { return }
        if let index = snapshot.spaceItems.firstIndex(where: { $0.spaceID == spaceID }) {
            let item = snapshot.spaceItems[index]
            let updatedItem = SpaceListSnapshot.SpaceItem(
                spaceID: item.spaceID,
                name: name,
                namespaceLabel: item.namespaceLabel,
                isSwitchable: item.isSwitchable
            )
            var items = snapshot.spaceItems
            items[index] = updatedItem
            snapshot = SpaceListSnapshot(
                spaceItems: items,
                updateInfo: snapshot.updateInfo,
                diagnosticsEnabled: snapshot.diagnosticsEnabled
            )
            self.snapshot = snapshot
        }
    }

    func requestMenuRebuild() {
        rebuildMenu()
    }

    #if DEBUG
    var debugMenuItemTitles: [String] {
        menu.items.map(\.title)
    }
    #endif
}
