import AppKit
import Core
import SwiftUI

final class SpaceSwitcherPanelManager: BaseSwitcherPanelManager<SpaceSwitcherSnapshot, SpaceSwitcherView, Int> {
    override func makeRootView(
        snapshot: SpaceSwitcherSnapshot,
        onSelect: @escaping (Int) -> Void,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) -> SpaceSwitcherView {
        SpaceSwitcherView(
            snapshot: snapshot,
            onSelect: onSelect,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
    }

    override func resizePanel(for snapshot: SpaceSwitcherSnapshot) {
        guard let panelPair else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let width = min(max(screenFrame.width * 0.32, 420), 560)
        let rowHeight: CGFloat = 38
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let visibleRows = max(snapshot.items.count, 1)
        let desiredHeight = headerHeight + CGFloat(visibleRows) * rowHeight + listPadding
        let height = min(desiredHeight, max(screenFrame.height - 80, headerHeight + rowHeight + listPadding))
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2 + 30,
            width: width,
            height: height
        )
        panelPair.window.setFrame(frame, display: true)
    }
}
