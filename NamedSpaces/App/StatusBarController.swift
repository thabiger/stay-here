import AppKit
import Core
import Foundation

final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var onOpenSettings: (() -> Void)?
    private var onCopyState: (() -> Void)?
    private var onOpenLogs: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var onSelectSpace: ((Int) -> Void)?

    func configure(
        onOpenSettings: @escaping () -> Void,
        onCopyState: @escaping () -> Void,
        onOpenLogs: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onSelectSpace: @escaping (Int) -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onCopyState = onCopyState
        self.onOpenLogs = onOpenLogs
        self.onQuit = onQuit
        self.onSelectSpace = onSelectSpace

        item.button?.title = "Unnamed space"
        item.menu = menu

        rebuildBaseMenu()
    }

    func setTitle(_ text: String) {
        item.button?.title = text
    }

    func rebuildSpaceItems(registry: SpaceRegistry) {
        menu.removeAllItems()
        let spaceIDs = registry.orderedSpaceIDs()
        for id in spaceIDs {
            let title = "\(registry.namespaceLabel(for: id))  \(registry.name(for: id))"
            let row = NSMenuItem(title: title, action: #selector(selectSpace(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = NSNumber(value: id)
            menu.addItem(row)
        }

        if !spaceIDs.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",").withTarget(self))

        let debug = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        debugMenu.addItem(NSMenuItem(title: "Copy space state", action: #selector(copyState), keyEquivalent: "").withTarget(self))
        debugMenu.addItem(NSMenuItem(title: "Open logs", action: #selector(openLogs), keyEquivalent: "").withTarget(self))
        debug.submenu = debugMenu
        menu.addItem(debug)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Named Spaces", action: #selector(quit), keyEquivalent: "q").withTarget(self))
    }

    private func rebuildBaseMenu() {
        menu.removeAllItems()
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func copyState() { onCopyState?() }
    @objc private func openLogs() { onOpenLogs?() }
    @objc private func quit() { onQuit?() }
    @objc private func selectSpace(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.intValue else { return }
        // Defer until menu tracking ends; Ctrl+N shortcuts are ignored while the menu is open.
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onSelectSpace?(id)
        }
    }
}

private extension NSMenuItem {
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
