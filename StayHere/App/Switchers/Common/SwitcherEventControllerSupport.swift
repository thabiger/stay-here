import CoreGraphics
import Core
import Foundation

protocol SwitcherEventSessionHandling: AnyObject {
    func switcherConfiguredShortcut() -> SpaceSwitcherShortcut
    func switcherHasActiveSession() -> Bool
    func switcherSessionModifiers() -> CGEventFlags?
    func switcherEnsureSessionAndMoveSelection(backward: Bool)
    func switcherCommitOrDismissActiveSession()
    func switcherCancelActiveSession()
}

final class SwitcherEventControllerSupport {
    private weak var handler: (any SwitcherEventSessionHandling)?

    init(handler: any SwitcherEventSessionHandling) {
        self.handler = handler
    }

    func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.type {
        case .keyDown:
            return handleKeyDown(event: event)
        case .flagsChanged:
            return handleFlagsChanged(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    internal func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let handler else { return Unmanaged.passUnretained(event) }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let eventFlags = event.flags
        let configuredShortcut = handler.switcherConfiguredShortcut()

        guard keycode == configuredShortcut.keyCode else {
            if handler.switcherHasActiveSession(), handler.switcherSessionModifiers() != nil {
                DispatchQueue.main.async { [weak handler] in
                    handler?.switcherCancelActiveSession()
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard eventFlags.contains(configuredShortcut.modifiers) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldGoBackward = shouldMoveBackward(event: event, shortcut: configuredShortcut)
        DispatchQueue.main.async { [weak handler] in
            handler?.switcherEnsureSessionAndMoveSelection(backward: shouldGoBackward)
        }
        return nil
    }

    internal func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let handler,
              let sessionModifiers = handler.switcherSessionModifiers() else {
            return Unmanaged.passUnretained(event)
        }

        let activeModifiers = modifierFlags(from: event.flags)
        guard activeModifiers.intersection(sessionModifiers).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak handler] in
            handler?.switcherCommitOrDismissActiveSession()
        }
        return nil
    }

    internal func modifierFlags(from flags: CGEventFlags) -> CGEventFlags {
        var active = CGEventFlags()
        for flag in [CGEventFlags.maskShift, .maskControl, .maskAlternate, .maskCommand] where flags.contains(flag) {
            active.insert(flag)
        }
        return active
    }

    private func shouldMoveBackward(event: CGEvent, shortcut: SpaceSwitcherShortcut) -> Bool {
        guard !shortcut.modifiers.contains(.maskShift) else { return false }
        return modifierFlags(from: event.flags) == shortcut.modifiers.union(.maskShift)
    }
}
