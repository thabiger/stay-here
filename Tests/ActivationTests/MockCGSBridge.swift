import Core

final class MockCGSBridge: CGSBridgeProtocol {
    var activeSpaceIDValue: Int?
    var managedSnapshotValue: CGSBridge.ManagedSnapshot
    var switchByDesktopShortcutHandler: (Int) -> Bool
    var spacesForWindowHandler: (Int) -> [Int]

    init(
        activeSpaceIDValue: Int? = nil,
        managedSnapshotValue: CGSBridge.ManagedSnapshot = .init(
            spaces: [],
            activeByDisplay: [:],
            orderedIDsByDisplay: [:]
        ),
        switchByDesktopShortcutHandler: @escaping (Int) -> Bool = { _ in true },
        spacesForWindowHandler: @escaping (Int) -> [Int] = { _ in [] }
    ) {
        self.activeSpaceIDValue = activeSpaceIDValue
        self.managedSnapshotValue = managedSnapshotValue
        self.switchByDesktopShortcutHandler = switchByDesktopShortcutHandler
        self.spacesForWindowHandler = spacesForWindowHandler
    }

    func activeSpaceID() -> Int? {
        activeSpaceIDValue
    }

    func managedSnapshot() -> CGSBridge.ManagedSnapshot {
        managedSnapshotValue
    }

    func managedSpaces() -> [SpaceIdentity] {
        managedSnapshotValue.spaces
    }

    func switchByDesktopShortcut(index: Int) -> Bool {
        switchByDesktopShortcutHandler(index)
    }

    func spacesForWindow(windowID: Int) -> [Int] {
        spacesForWindowHandler(windowID)
    }
}
