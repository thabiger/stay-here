import AppKit

enum WindowSwitcherPanelLayout {
    static func panelHeight(
        spaceGroupCount: Int,
        totalWindowCount: Int,
        screenHeight: CGFloat
    ) -> CGFloat {
        let rowHeight: CGFloat = 40
        let sectionHeaderHeight: CGFloat = 28
        let headerHeight: CGFloat = 54
        let listPadding: CGFloat = 20
        let emptyBodyHeight: CGFloat = 56
        let bodyHeight = totalWindowCount == 0
            ? emptyBodyHeight
            : CGFloat(spaceGroupCount) * sectionHeaderHeight
              + CGFloat(totalWindowCount) * rowHeight
              + listPadding
        let minimumHeight = headerHeight + min(emptyBodyHeight, rowHeight + listPadding)
        let maxHeight = max(screenHeight - 80, minimumHeight)
        return min(headerHeight + bodyHeight, maxHeight)
    }
}
