import AppKit
import Core
import Foundation

@MainActor
@objc protocol StatusBarMenuActionHandler: AnyObject {
    func openSettings()
    func openAbout()
    func checkForUpdates()
    func openAvailableUpdate()
    func copyState()
    func openLogs()
    func quit()
}

final class StatusBarMenuBuilder {
    func buildMenuItems(
        from snapshot: SpaceListSnapshot,
        coordinator: SpaceMenuRowViewCoordinating,
        target: StatusBarMenuActionHandler
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        items.append(contentsOf: buildSpaceItems(from: snapshot, coordinator: coordinator))

        if !snapshot.spaceItems.isEmpty {
            items.append(.separator())
        }

        items.append(contentsOf: buildStaticItems(from: snapshot, target: target))

        return items
    }

    private func buildSpaceItems(
        from snapshot: SpaceListSnapshot,
        coordinator: SpaceMenuRowViewCoordinating
    ) -> [NSMenuItem] {
        snapshot.spaceItems.map { item in
            let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menuItem.representedObject = NSNumber(value: item.spaceID)
            menuItem.isEnabled = item.isSwitchable
            menuItem.view = SpaceMenuRowView(
                spaceID: item.spaceID,
                namespaceLabel: item.namespaceLabel,
                name: item.name,
                controller: coordinator
            )
            return menuItem
        }
    }

    private func buildStaticItems(from snapshot: SpaceListSnapshot, target: StatusBarMenuActionHandler) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if snapshot.updateInfo != nil {
            items.append(NSMenuItem(
                title: "Update Available…",
                action: #selector(StatusBarMenuActionHandler.openAvailableUpdate),
                keyEquivalent: ""
            ).withTarget(target))
        }

        items.append(NSMenuItem(
            title: "Check for Updates…",
            action: #selector(StatusBarMenuActionHandler.checkForUpdates),
            keyEquivalent: ""
        ).withTarget(target))

        items.append(NSMenuItem(
            title: "Settings…",
            action: #selector(StatusBarMenuActionHandler.openSettings),
            keyEquivalent: ","
        ).withTarget(target))

        items.append(NSMenuItem(
            title: "About StayHere",
            action: #selector(StatusBarMenuActionHandler.openAbout),
            keyEquivalent: ""
        ).withTarget(target))

        if snapshot.diagnosticsEnabled {
            let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            let debugMenu = NSMenu()
            debugMenu.addItem(NSMenuItem(
                title: "Copy space state",
                action: #selector(StatusBarMenuActionHandler.copyState),
                keyEquivalent: ""
            ).withTarget(target))
            debugMenu.addItem(NSMenuItem(
                title: "Open logs",
                action: #selector(StatusBarMenuActionHandler.openLogs),
                keyEquivalent: ""
            ).withTarget(target))
            debugItem.submenu = debugMenu
            items.append(debugItem)
        }

        items.append(.separator())

        items.append(NSMenuItem(
            title: "Quit StayHere",
            action: #selector(StatusBarMenuActionHandler.quit),
            keyEquivalent: "q"
        ).withTarget(target))

        return items
    }
}

private extension NSMenuItem {
    func withTarget(_ target: StatusBarMenuActionHandler) -> NSMenuItem {
        self.target = target
        return self
    }
}
