import AppKit
import Core
import Foundation

final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let spacesItem = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
    private let spacesSubmenu = NSMenu()

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

    func rebuildSpaceSubmenu(registry: SpaceRegistry) {
        spacesSubmenu.removeAllItems()
        for id in registry.orderedSpaceIDs() {
            let title = "\(registry.namespaceLabel(for: id))  \(registry.name(for: id))"
            let row = NSMenuItem(title: title, action: #selector(selectSpace(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = NSNumber(value: id)
            if id == registry.activeSpaceID { row.state = .on }
            spacesSubmenu.addItem(row)
        }
    }

    private func rebuildBaseMenu() {
        menu.removeAllItems()
        spacesItem.submenu = spacesSubmenu
        menu.addItem(spacesItem)

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

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func copyState() { onCopyState?() }
    @objc private func openLogs() { onOpenLogs?() }
    @objc private func quit() { onQuit?() }
    @objc private func selectSpace(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.intValue else { return }
        // Defer until menu tracking ends; Ctrl+N shortcuts are ignored while the menu is open.
        spacesSubmenu.cancelTracking()
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
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
