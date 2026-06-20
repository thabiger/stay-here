import AppKit
import CoreGraphics
import Core
import SwiftUI

final class WindowSwitcherController {
    let mode: WindowSwitcherMode
    let settings: WindowSwitcherSettings & AllSpacesWindowSwitcherSettings
    let registry: SpaceRegistry
    let shortcutProvider: () -> SpaceSwitcherShortcut
    let recencyTracker: WindowRecencyTracker
    let listBuilder: WindowListBuilder
    let panelPresenter: WindowSwitcherPanelPresenter
    private let windowSwitchUseCase: WindowSwitchUseCase
    private let listProvider: WindowListProvider

    private lazy var coordinator = SwitcherSessionCoordinator<
        WindowSwitcherSession,
        WindowSwitcherSnapshot,
        Int
    >(
        shortcutProvider: { [weak self] in
            self?.shortcutProvider() ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
        },
        movesSelectionOnNewSession: false,
        buildSession: { [weak self] shortcut, trigger in
            guard let self, let source = self.listBuilder.makeSessionSource() else { return nil }
            return WindowSwitcherSession(
                startingWindowID: source.startingWindowID,
                selectedWindowID: source.flatEntries.first?.windowID,
                shortcut: shortcut,
                spaceGroups: source.spaceGroups,
                flatEntries: source.flatEntries,
                trigger: trigger
            )
        },
        moveSelection: { session, offset in
            let entries = session.flatEntries
            guard !entries.isEmpty else { return }
            let ids = entries.map(\.windowID)
            let currentSelection = session.selectedWindowID ?? session.startingWindowID ?? ids.first
            let nextSelection = offset > 0
                ? WindowSwitcherSelection.nextWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
                : WindowSwitcherSelection.previousWindowID(currentWindowID: currentSelection, orderedWindowIDs: ids)
            session.selectedWindowID = nextSelection
        },
        buildSnapshot: { [weak self] session in
            self?.listBuilder.buildSnapshot(for: session)
                ?? WindowSwitcherSnapshot(
                    spaceGroups: [],
                    title: "Window Switcher",
                    subtitle: "0 windows",
                    emptyMessage: "No windows",
                    iconName: "macwindow",
                    showSpaceLabels: false
                )
        },
        itemAtPosition: { session, position in
            guard let session, position > 0, position <= session.flatEntries.count else { return nil }
            return session.flatEntries[position - 1].windowID
        },
        shouldCommit: { _ in true },
        commitSelection: { [weak self] session, windowID in
            guard let self, let session, let entry = session.flatEntries.first(where: { $0.windowID == windowID }) else {
                return false
            }
            self.recencyTracker.recordSelection(windowID, in: session)
            self.commitSelectedEntry(entry)
            return true
        },
        presentSnapshot: { [weak self] snapshot, onSelect, onFocusLost, onCommit, onCancel, onMoveUp, onMoveDown, updateInfo, onOpenUpdate in
            self?.panelPresenter.present(
                snapshot: snapshot,
                onSelect: { entry in onSelect(entry.windowID) },
                onFocusLost: onFocusLost,
                onCommit: onCommit,
                onCancel: onCancel,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                updateInfo: updateInfo,
                onOpenUpdate: onOpenUpdate
            )
        },
        dismissPanel: { [weak self] in
            self?.panelPresenter.dismiss()
        },
        releasePanel: { [weak self] in
            self?.panelPresenter.release()
        }
    )

    var panelPair: (window: NSPanel, hosting: NSHostingController<WindowSwitcherView>)? {
        get { panelPresenter.panelPair }
        set { panelPresenter.panelPair = newValue }
    }

    internal var testSessionEntries: [WindowEntry]? {
        coordinator.testSession?.flatEntries
    }

    internal var testSessionSpaceID: Int? {
        coordinator.testSession?.spaceGroups.first?.spaceID
    }

    internal var testSessionSpaceGroups: [WindowListProvider.SpaceWindowGroup]? {
        coordinator.testSession?.spaceGroups
    }

    internal var testSessionSelectedWindowID: Int? {
        coordinator.testSession?.selectedWindowID
    }

    internal var testRecentWindowIDs: [Int] {
        recencyTracker.recentWindowIDs
    }

    init(
        settings: WindowSwitcherSettings & AllSpacesWindowSwitcherSettings,
        registry: SpaceRegistry,
        mode: WindowSwitcherMode,
        windowSwitchUseCase: WindowSwitchUseCase? = nil,
        shortcutProvider: (() -> SpaceSwitcherShortcut)? = nil,
        listProvider: WindowListProvider? = nil,
        cgsBridge: any CGSBridgeProtocol = CGSBridge.live,
        switchSpace: SwitchSpaceUseCase? = nil,
        refreshSpaces: RefreshSpacesUseCase? = nil,
        focusService: WindowFocusService = WindowFocusService(),
        recencyTracker: WindowRecencyTracker? = nil,
        listBuilder: WindowListBuilder? = nil,
        panelPresenter: WindowSwitcherPanelPresenter? = nil
    ) {
        self.mode = mode
        self.settings = settings
        self.registry = registry

        let resolvedShortcut = shortcutProvider ?? {
            switch mode {
            case .currentSpace:
                return SpaceSwitcherShortcut.parse(settings.windowSwitcherShortcutText)
                    ?? SpaceSwitcherShortcut.parse("command+`")
                    ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand])
            case .allSpaces:
                return SpaceSwitcherShortcut.parse(settings.allSpacesWindowSwitcherShortcutText)
                    ?? SpaceSwitcherShortcut.parse("command+shift+`")
                    ?? SpaceSwitcherShortcut(keyCode: 50, modifiers: [.maskCommand, .maskShift])
            }
        }
        self.shortcutProvider = resolvedShortcut

        self.listProvider = listProvider ?? WindowListProvider(
            registry: registry,
            cgsBridge: cgsBridge,
            settings: settings
        )
        self.recencyTracker = recencyTracker ?? WindowRecencyTracker()
        self.listBuilder = listBuilder ?? WindowListBuilder(
            mode: mode,
            listProvider: self.listProvider,
            recencyTracker: self.recencyTracker,
            registry: registry,
            settings: settings
        )
        self.panelPresenter = panelPresenter ?? WindowSwitcherPanelPresenter()

        self.windowSwitchUseCase = windowSwitchUseCase ?? WindowSwitchUseCase(dependencies: .init(
            cgsBridge: cgsBridge,
            listProvider: self.listProvider,
            switchSpace: switchSpace ?? SwitchSpaceUseCase(
                cgsBridge: cgsBridge,
                repository: SpaceStateManager(cgsBridge: cgsBridge, logger: NoOpLogger()),
                refreshUseCase: refreshSpaces ?? RefreshSpacesUseCase(repository: SpaceStateManager(cgsBridge: cgsBridge, logger: NoOpLogger()), logger: NoOpLogger()),
                logger: NoOpLogger()
            ),
            refreshSpaces: refreshSpaces ?? RefreshSpacesUseCase(repository: SpaceStateManager(cgsBridge: cgsBridge, logger: NoOpLogger()), logger: NoOpLogger()),
            focusService: focusService
        ))

    }


    var hasActiveSession: Bool { coordinator.hasActiveSession }

    deinit {
        stop()
    }

    func start() {
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
    }

    internal func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handle(event: event)
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handleKeyDown(event: event)
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        coordinator.handleFlagsChanged(event: event)
    }

    internal func cancelSession() {
        coordinator.cancelSession()
    }

    func setAvailableUpdate(_ updateInfo: UpdateInfo?) {
        coordinator.setAvailableUpdate(updateInfo)
    }

    func setOnOpenUpdate(_ callback: @escaping () -> Void) {
        coordinator.setOnOpenUpdate(callback)
    }

    func openSwitcher() {
        coordinator.openSwitcher()
    }

    func moveSelectionForward() {
        coordinator.moveSelectionForward()
    }

    func moveSelectionBackward() {
        coordinator.moveSelectionBackward()
    }

    func commitSwitcherSelection() {
        coordinator.commitSwitcherSelection()
    }

    internal func switcherCommitOrDismissActiveSession() {
        coordinator.commitSwitcherSelection()
    }

    func commitSelection(at position: Int) {
        coordinator.commitSelection(at: position)
    }

    func closeSwitcher() {
        coordinator.closeSwitcher()
    }

    private func commitSelectedEntry(_ entry: WindowEntry) {
        let previousSpaceID = listProvider.currentContext()?.spaceID
        panelPresenter.dismiss()
        coordinator.closeSwitcher()

        Task { @MainActor [weak self] in
            await self?.windowSwitchUseCase.execute(entry: entry, previousSpaceID: previousSpaceID)
        }
    }
}
