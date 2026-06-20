import AppKit
import Core
import Foundation

struct SpaceListSnapshot {
    struct SpaceItem: Equatable {
        let spaceID: Int
        let name: String
        let namespaceLabel: String
        let isSwitchable: Bool
    }

    let spaceItems: [SpaceItem]
    let updateInfo: UpdateInfo?
    let diagnosticsEnabled: Bool

    static func build(
        from registry: SpaceRegistry,
        updateInfo: UpdateInfo?,
        diagnosticsEnabled: Bool
    ) -> SpaceListSnapshot {
        let spaceIDs = registry.switchableOrderedSpaceIDs()
        let items = spaceIDs.map { id in
            SpaceItem(
                spaceID: id,
                name: registry.displayName(for: id),
                namespaceLabel: registry.namespaceLabel(for: id),
                isSwitchable: registry.isSwitchableSpace(id)
            )
        }
        return SpaceListSnapshot(
            spaceItems: items,
            updateInfo: updateInfo,
            diagnosticsEnabled: diagnosticsEnabled
        )
    }
}
