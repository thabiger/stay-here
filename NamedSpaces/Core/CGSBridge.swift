import Foundation
import CoreGraphics
import AppKit

public enum CGSBridge {
    private typealias CGSConnectionID = UInt32
    private typealias CGSSpaceID = UInt64

    private static let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    public static func activeSpaceID() -> Int? {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias GetActive = @convention(c) (CGSConnectionID) -> CGSSpaceID

        guard let main: MainConn = symbol("_CGSDefaultConnection", as: MainConn.self) ?? symbol("CGSMainConnectionID", as: MainConn.self),
              let getActive: GetActive = symbol("CGSGetActiveSpace", as: GetActive.self) else {
            return nil
        }

        let id = getActive(main())
        return id == 0 ? nil : Int(id)
    }

    public struct ManagedSnapshot {
        public let spaces: [SpaceIdentity]
        public let activeByDisplay: [String: Int]
        /// Mission Control order per display (matches Ctrl+number shortcuts).
        public let orderedIDsByDisplay: [String: [Int]]
    }

    public static func managedSnapshot() -> ManagedSnapshot {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias CopyManaged = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?

        guard let main: MainConn = symbol("_CGSDefaultConnection", as: MainConn.self) ?? symbol("CGSMainConnectionID", as: MainConn.self),
              let copyManaged: CopyManaged = symbol("CGSCopyManagedDisplaySpaces", as: CopyManaged.self),
              let array = copyManaged(main())?.takeRetainedValue() as? [[String: Any]] else {
            return ManagedSnapshot(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
        }

        var spaces: [SpaceIdentity] = []
        var activeByDisplay: [String: Int] = [:]
        var orderedIDsByDisplay: [String: [Int]] = [:]
        for displayEntry in array {
            let display = (displayEntry["Display Identifier"] as? String) ?? "unknown-display"
            if let current = displayEntry["Current Space"] as? [String: Any],
               let spaceID = parsedSpaceID(from: current) {
                activeByDisplay[display] = spaceID
            }
            let managed = displayEntry["Spaces"] as? [[String: Any]] ?? []
            var ordered: [Int] = []
            for space in managed {
                if let spaceID = parsedSpaceID(from: space) {
                    ordered.append(spaceID)
                    spaces.append(SpaceIdentity(id: spaceID, display: display))
                }
            }
            orderedIDsByDisplay[display] = ordered
        }
        return ManagedSnapshot(spaces: spaces, activeByDisplay: activeByDisplay, orderedIDsByDisplay: orderedIDsByDisplay)
    }

    public static func managedSpaces() -> [SpaceIdentity] {
        managedSnapshot().spaces
    }

    /// Posts Ctrl+1…6 to match Mission Control desktop shortcuts.
    public static func switchByDesktopShortcut(index: Int) -> Bool {
        guard (1...6).contains(index) else { return false }
        let keyCodes: [Int: CGKeyCode] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22,
        ]
        guard let keyCode = keyCodes[index] else { return false }
        return postControlKey(keyCode: keyCode)
    }

    public static func moveWindowToSpace(windowID: Int, spaceID: Int) -> Bool {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias Move = @convention(c) (CGSConnectionID, CFArray, CGSSpaceID) -> Int32

        guard let main: MainConn = symbol("_CGSDefaultConnection", as: MainConn.self) ?? symbol("CGSMainConnectionID", as: MainConn.self),
              let move: Move = symbol("CGSMoveWindowsToManagedSpace", as: Move.self) else {
            return false
        }

        let ids: [NSNumber] = [NSNumber(value: windowID)]
        let rc = move(main(), ids as CFArray, CGSSpaceID(spaceID))
        return rc == 0
    }

    public static func spacesForWindow(windowID: Int) -> [Int] {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias CopySpacesForWindows = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

        guard let main: MainConn = symbol("_CGSDefaultConnection", as: MainConn.self) ?? symbol("CGSMainConnectionID", as: MainConn.self),
              let copySpaces: CopySpacesForWindows = symbol("CGSCopySpacesForWindows", as: CopySpacesForWindows.self) else {
            return []
        }

        // 0x7 matches the common "all spaces" selector used in CGS prior art.
        let windowIDs: [NSNumber] = [NSNumber(value: windowID)]
        guard let raw = copySpaces(main(), 0x7, windowIDs as CFArray)?.takeRetainedValue() else {
            return []
        }

        if let ids = raw as? [NSNumber] {
            return ids.map(\.intValue)
        }
        return []
    }

    private static func postControlKey(keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    private static func parsedSpaceID(from payload: [String: Any]) -> Int? {
        if let id64 = payload["id64"] as? NSNumber {
            return id64.intValue
        }
        if let id64 = payload["id64"] as? String, let value = Int(id64) {
            return value
        }
        if let managed = payload["ManagedSpaceID"] as? NSNumber {
            return managed.intValue
        }
        if let managed = payload["ManagedSpaceID"] as? String, let value = Int(managed) {
            return value
        }
        return nil
    }
}
