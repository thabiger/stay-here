import AppKit
import Combine
import Core

@MainActor
final class StatusBarCoordinator {
    private let statusController: StatusBarController
    private let registry: SpaceRegistry
    private let settings: SettingsRepository

    private var cancellables: Set<AnyCancellable> = []
    private var menuRebuildWorkItem: DispatchWorkItem?
    private var isSettingsOpen: () -> Bool = { false }

    init(
        statusController: StatusBarController,
        registry: SpaceRegistry,
        settings: SettingsRepository
    ) {
        self.statusController = statusController
        self.registry = registry
        self.settings = settings
    }

    var isEditingSpaceName: Bool {
        statusController.isEditingSpaceName
    }

    func bindSettingsOpen(_ isSettingsOpen: @escaping () -> Bool) {
        self.isSettingsOpen = isSettingsOpen
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
        statusController.configure(
            onOpenSettings: onOpenSettings,
            onOpenAbout: onOpenAbout,
            onCheckForUpdates: onCheckForUpdates,
            onOpenAvailableUpdate: onOpenAvailableUpdate,
            onCopyState: onCopyState,
            onOpenLogs: onOpenLogs,
            onQuit: onQuit,
            onSelectSpace: onSelectSpace,
            onRenameSpace: onRenameSpace
        )
    }

    func setTitle(_ title: String) {
        statusController.setTitle(title)
    }

    func rebuildSpaceItems() {
        guard !isSettingsOpen(), !statusController.isEditingSpaceName else { return }
        menuRebuildWorkItem?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.isSettingsOpen(), !self.statusController.isEditingSpaceName else { return }
            self.statusController.rebuildSpaceItems(registry: self.registry)
        }
        menuRebuildWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    func applyCurrentAppearance() {
        statusController.applyCurrentAppearance()
    }
}
