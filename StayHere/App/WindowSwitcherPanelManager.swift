import AppKit
import Core
import SwiftUI

final class WindowSwitcherPanelManager: BaseSwitcherPanelManager<WindowSwitcherSnapshot, WindowSwitcherView, WindowEntry> {
    override func makeRootView(
        snapshot: WindowSwitcherSnapshot,
        onSelect: @escaping (WindowEntry) -> Void,
        updateInfo: UpdateInfo?,
        onOpenUpdate: (() -> Void)?
    ) -> WindowSwitcherView {
        WindowSwitcherView(
            snapshot: snapshot,
            onSelect: onSelect,
            updateInfo: updateInfo,
            onOpenUpdate: onOpenUpdate
        )
    }

    override func resizePanel(for snapshot: WindowSwitcherSnapshot) {
        guard let panelPair else { return }
        let width: CGFloat = 560
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let totalItemCount = snapshot.spaceGroups.reduce(0) { $0 + $1.items.count }
        let groupCount = snapshot.showSpaceLabels ? snapshot.spaceGroups.count : 0
        let height = WindowSwitcherPanelLayout.panelHeight(
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
