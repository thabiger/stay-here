import Foundation
import CoreGraphics
import AppKit

public protocol CGSBridgeProtocol {
    func activeSpaceID() -> Int?
    func managedSnapshot() -> CGSBridge.ManagedSnapshot
    func managedSpaces() -> [SpaceIdentity]
    func switchByDesktopShortcut(index: Int) -> Bool
    func spacesForWindow(windowID: Int) -> [Int]
}

public struct CGSBridge: CGSBridgeProtocol {
    private typealias CGSConnectionID = UInt32
    private typealias CGSSpaceID = UInt64

    public static let live = CGSBridge()

    private static let handle: UnsafeMutableRawPointer? = {
        if RuntimeEnvironment.isAutomationSession { return nil }
        return dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    }()

    public init() {}

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    public func activeSpaceID() -> Int? {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias GetActive = @convention(c) (CGSConnectionID) -> CGSSpaceID

        guard let main: MainConn = Self.symbol("_CGSDefaultConnection", as: MainConn.self) ?? Self.symbol("CGSMainConnectionID", as: MainConn.self),
              let getActive: GetActive = Self.symbol("CGSGetActiveSpace", as: GetActive.self) else {
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

        public init(
            spaces: [SpaceIdentity],
            activeByDisplay: [String: Int],
            orderedIDsByDisplay: [String: [Int]]
        ) {
            self.spaces = spaces
            self.activeByDisplay = activeByDisplay
            self.orderedIDsByDisplay = orderedIDsByDisplay
        }
    }

    public func managedSnapshot() -> ManagedSnapshot {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias CopyManaged = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?

        guard let main: MainConn = Self.symbol("_CGSDefaultConnection", as: MainConn.self) ?? Self.symbol("CGSMainConnectionID", as: MainConn.self),
              let copyManaged: CopyManaged = Self.symbol("CGSCopyManagedDisplaySpaces", as: CopyManaged.self),
              let array = copyManaged(main())?.takeRetainedValue() as? [[String: Any]] else {
            return ManagedSnapshot(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
        }

        var spaces: [SpaceIdentity] = []
        var activeByDisplay: [String: Int] = [:]
        var orderedIDsByDisplay: [String: [Int]] = [:]
        for displayEntry in array {
            let display = (displayEntry["Display Identifier"] as? String) ?? "unknown-display"
            if let current = displayEntry["Current Space"] as? [String: Any],
               let spaceID = Self.parsedSpaceID(from: current) {
                activeByDisplay[display] = spaceID
            }
            let managed = displayEntry["Spaces"] as? [[String: Any]] ?? []
            var ordered: [Int] = []
            for space in managed {
                if let spaceID = Self.parsedSpaceID(from: space) {
                    ordered.append(spaceID)
                    spaces.append(
                        SpaceIdentity(
                            id: spaceID,
                            display: display,
                            kind: Self.parsedSpaceKind(from: space),
                            systemName: Self.parsedSpaceName(from: space)
                        )
                    )
                }
            }
            orderedIDsByDisplay[display] = ordered
        }
        return ManagedSnapshot(spaces: spaces, activeByDisplay: activeByDisplay, orderedIDsByDisplay: orderedIDsByDisplay)
    }

    public func managedSpaces() -> [SpaceIdentity] {
        managedSnapshot().spaces
    }

    /// Posts Ctrl+1…9 to match Mission Control desktop shortcuts.
    public func switchByDesktopShortcut(index: Int) -> Bool {
        guard (1...9).contains(index) else { return false }
        let keyCodes: [Int: CGKeyCode] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22,
            7: 26, 8: 28, 9: 25,
        ]
        guard let keyCode = keyCodes[index] else { return false }
        return Self.postControlKey(keyCode: keyCode)
    }

    public func spacesForWindow(windowID: Int) -> [Int] {
        typealias MainConn = @convention(c) () -> CGSConnectionID
        typealias CopySpacesForWindows = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

        guard let main: MainConn = Self.symbol("_CGSDefaultConnection", as: MainConn.self) ?? Self.symbol("CGSMainConnectionID", as: MainConn.self),
              let copySpaces: CopySpacesForWindows = Self.symbol("CGSCopySpacesForWindows", as: CopySpacesForWindows.self) else {
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

    private static func parsedSpaceKind(from payload: [String: Any]) -> SpaceKind {
        if let type = payload["type"] as? NSNumber {
            switch type.intValue {
            case 0:
                return .desktop
            case 4:
                return .fullscreen
            default:
                return .unknown
            }
        }
        if let tileLayoutManager = payload["TileLayoutManager"] as? [String: Any],
           tileLayoutManager.isEmpty == false {
            return .fullscreen
        }
        return .unknown
    }

    private static func parsedSpaceName(from payload: [String: Any]) -> String? {
        let candidates: [Any?] = [
            payload["name"],
            payload["Name"],
            payload["title"],
            payload["Title"]
        ]
        for candidate in candidates {
            if let value = (candidate as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }
        if let tileLayoutManager = payload["TileLayoutManager"] as? [String: Any] {
            for key in ["name", "Name", "title", "Title"] {
                if let value = (tileLayoutManager[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   value.isEmpty == false {
                    return value
                }
            }
        }
        return nil
    }
}
