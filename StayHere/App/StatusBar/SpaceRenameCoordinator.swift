import AppKit
import Foundation

final class SpaceRenameCoordinator: SpaceMenuRowViewCoordinating {
    private weak var editingRow: SpaceMenuRowView?
    private var editingSpaceID: Int?
    private var suppressNextEditRebuild = false

    private let appearanceManager: AppearanceManager
    private var onRenameSpace: ((Int, String) -> Void)?
    private var onSelectSpace: ((Int) -> Void)?
    private weak var menuProvider: (any SpaceMenuProviding)?

    var isEditingSpaceName: Bool {
        editingSpaceID != nil
    }

    var currentAppearance: NSAppearance? {
        appearanceManager.currentAppearance
    }

    init(appearanceManager: AppearanceManager) {
        self.appearanceManager = appearanceManager
    }

    func setMenuProvider(_ provider: any SpaceMenuProviding) {
        self.menuProvider = provider
    }

    func configure(
        onRenameSpace: @escaping (Int, String) -> Void,
        onSelectSpace: @escaping (Int) -> Void
    ) {
        self.onRenameSpace = onRenameSpace
        self.onSelectSpace = onSelectSpace
    }

    func beginEditing(row: SpaceMenuRowView, spaceID: Int) -> Bool {
        if let editingSpaceID, editingSpaceID != spaceID {
            suppressNextEditRebuild = true
            editingRow?.commitEditFromController()
        }
        guard editingSpaceID == nil || editingSpaceID == spaceID else { return false }
        editingSpaceID = spaceID
        editingRow = row
        menuProvider?.setMenuItemsEnabledForEditing(activeSpaceID: spaceID)
        return true
    }

    func finishEditing(row: SpaceMenuRowView, spaceID: Int, name: String, commit: Bool) {
        guard editingSpaceID == spaceID, editingRow === row else { return }
        suppressNextEditRebuild = false
        editingSpaceID = nil
        editingRow = nil
        menuProvider?.setAllMenuItemsEnabled(true)
        if commit {
            menuProvider?.updateSpaceName(spaceID: spaceID, name: name)
            onRenameSpace?(spaceID, name)
        }
        if !suppressNextEditRebuild {
            menuProvider?.requestMenuRebuild()
        }
    }

    func commitActiveEdit() {
        editingRow?.commitEditFromController()
    }

    func selectSpace(_ spaceID: Int) {
        guard !isEditingSpaceName else { return }
        guard menuProvider?.isSwitchableSpace(spaceID) == true else { return }
        menuProvider?.performSpaceSelection(spaceID)
    }
}

@MainActor
protocol SpaceMenuProviding: AnyObject {
    var isEditingSpaceName: Bool { get }
    func isSwitchableSpace(_ spaceID: Int) -> Bool
    func setMenuItemsEnabledForEditing(activeSpaceID: Int)
    func setAllMenuItemsEnabled(_ enabled: Bool)
    func requestMenuRebuild()
    func performSpaceSelection(_ spaceID: Int)
    func updateSpaceName(spaceID: Int, name: String)
}
