import AppKit
import Core
import SwiftUI

final class AllSpacesWindowSwitcherPanelManager: BaseWindowPanelManager<AllSpacesWindowSwitcherSnapshot, AllSpacesWindowSwitcherView> {
    override func makeRootView(
        snapshot: AllSpacesWindowSwitcherSnapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) -> AllSpacesWindowSwitcherView {
        AllSpacesWindowSwitcherView(
            snapshot: snapshot,
            onSelect: onSelect,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
    }

    override func resizePanel(for snapshot: AllSpacesWindowSwitcherSnapshot) {
        guard let panelPair else { return }
        let width: CGFloat = 560
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let totalItemCount = snapshot.spaceGroups.reduce(0) { $0 + $1.items.count }
        let groupCount = snapshot.spaceGroups.count
        let height = AllSpacesWindowSwitcherController.panelHeight(
            spaceGroupCount: groupCount,
            totalWindowCount: totalItemCount,
            screenHeight: screenFrame.height
        )
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }
}
