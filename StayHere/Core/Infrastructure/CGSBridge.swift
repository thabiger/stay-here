import Foundation
import CoreGraphics

public protocol CGSBridgeProtocol {
    func activeSpaceID() -> Int?
    func managedSnapshot() -> CGSBridge.ManagedSnapshot
    func managedSpaces() -> [SpaceIdentity]
    func switchByDesktopShortcut(index: Int) -> Bool
    func spacesForWindow(windowID: Int) -> [Int]
    func clearSpacesCache()
    func bridgeHealth() -> CGSBridge.HealthReport
}

extension CGSBridgeProtocol {
    /// Default: no-op. Keeps test mocks compiling unchanged;
    /// only the real CGSBridge clears its memoization cache.
    public func clearSpacesCache() {}
    /// Default: not applicable. Keeps test mocks compiling unchanged;
    /// only the real CGSBridge reports actual symbol resolution.
    public func bridgeHealth() -> CGSBridge.HealthReport { .notApplicable }
}

public struct CGSBridge: CGSBridgeProtocol {
    private typealias CGSConnectionID = UInt32
    private typealias CGSSpaceID = UInt64

    /// Single source of truth for the private CGS symbol surface.
    /// Keep in sync with docs/cgs-bridge.md.
    private enum CGSSymbol {
        static let defaultConnection = "_CGSDefaultConnection"
        static let mainConnectionFallback = "CGSMainConnectionID"
        static let getActiveSpace = "CGSGetActiveSpace"
        static let copyManagedDisplaySpaces = "CGSCopyManagedDisplaySpaces"
        static let copySpacesForWindows = "CGSCopySpacesForWindows"
    }

    private typealias MainConn = @convention(c) () -> CGSConnectionID
    private typealias GetActive = @convention(c) (CGSConnectionID) -> CGSSpaceID
    private typealias CopyManaged = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?

    public static let live = CGSBridge()

    private static let spacesCache = CGSSpacesCache()

    private static let handle: UnsafeMutableRawPointer? = {
        if RuntimeEnvironment.isAutomationSession { return nil }
        return dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    }()

    private static let defaultConnectionSymbol: MainConn? = symbol(CGSSymbol.defaultConnection, as: MainConn.self)
    private static let mainConnectionFallbackSymbol: MainConn? = symbol(CGSSymbol.mainConnectionFallback, as: MainConn.self)
    private static let mainConn: MainConn? = defaultConnectionSymbol ?? mainConnectionFallbackSymbol
    private static let activeSpaceSymbol: GetActive? = symbol(CGSSymbol.getActiveSpace, as: GetActive.self)
    private static let copyManagedSpacesSymbol: CopyManaged? = symbol(CGSSymbol.copyManagedDisplaySpaces, as: CopyManaged.self)
    private static let copySpacesForWindowsSymbol: CopySpacesForWindows? = symbol(CGSSymbol.copySpacesForWindows, as: CopySpacesForWindows.self)

    public init() {}

    /// Clears the memoization cache. Called when space-filtering settings change
    /// so stale CGS results are not served after invalidation.
    public static func clearSpacesCache() {
        spacesCache.clear()
    }

    public func clearSpacesCache() {
        Self.clearSpacesCache()
    }

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    public func activeSpaceID() -> Int? {
        guard let main = Self.mainConn,
              let getActive = Self.activeSpaceSymbol else {
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

    public struct HealthReport: Equatable {
        public enum SymbolRole: Equatable { case critical, required, optional }
        public struct SymbolStatus: Equatable {
            public let symbol: String
            public let resolved: Bool
            public let role: SymbolRole
        }
        public let symbols: [SymbolStatus]
        /// True when the managedSnapshot() smoke probe returned any data.
        public let payloadProbeSucceeded: Bool

        public init(symbols: [SymbolStatus], payloadProbeSucceeded: Bool) {
            self.symbols = symbols
            self.payloadProbeSucceeded = payloadProbeSucceeded
        }

        /// Healthy = all critical+required symbols resolved and probe succeeded.
        /// Missing optional symbols degrade a feature but do not fail the check.
        public var isHealthy: Bool {
            symbols.filter { $0.role != .optional }.allSatisfy(\.resolved) && payloadProbeSucceeded
        }

        /// Human-readable degraded-feature summary for log/diagnostics.
        public var degradedFeatureSummary: String {
            let missing = symbols.filter { !$0.resolved }
            guard !missing.isEmpty else {
                return "all symbols resolved" + (payloadProbeSucceeded ? "" : "; payload probe failed")
            }
            let parts = missing.map { "\($0.symbol) (\($0.role))" }
            return "missing: " + parts.joined(separator: ", ") + (payloadProbeSucceeded ? "" : "; payload probe failed")
        }

        public static let notApplicable = HealthReport(symbols: [], payloadProbeSucceeded: true)
    }

    public func managedSnapshot() -> ManagedSnapshot {
        guard let main = Self.mainConn,
              let copyManaged = Self.copyManagedSpacesSymbol,
              let array = copyManaged(main())?.takeRetainedValue() as? [[String: Any]] else {
            return ManagedSnapshot(spaces: [], activeByDisplay: [:], orderedIDsByDisplay: [:])
        }

        var spaces: [SpaceIdentity] = []
        var activeByDisplay: [String: Int] = [:]
        var orderedIDsByDisplay: [String: [Int]] = [:]
        for displayEntry in array {
            let display = (displayEntry["Display Identifier"] as? String) ?? SpaceLabelStore.unknownDisplayIdentifier
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
        if let cached = Self.spacesCache.resolved(windowID: windowID) {
            return cached
        }

        guard let main = Self.mainConn,
              let copySpaces = Self.copySpacesForWindowsSymbol else {
            return []
        }

        // 0x7 matches the common "all spaces" selector used in CGS prior art.
        let windowIDs: [NSNumber] = [NSNumber(value: windowID)]
        guard let raw = copySpaces(main(), 0x7, windowIDs as CFArray)?.takeRetainedValue() else {
            return []
        }

        if let ids = raw as? [NSNumber] {
            let spaces = ids.map(\.intValue)
            Self.spacesCache.store(windowID: windowID, spaces: spaces)
            return spaces
        }
        return []
    }

    public func bridgeHealth() -> HealthReport {
        guard !RuntimeEnvironment.isAutomationSession else { return .notApplicable }
        let handleResolved = Self.handle != nil
        let connectionResolved = Self.defaultConnectionSymbol != nil || Self.mainConnectionFallbackSymbol != nil
        let getActiveResolved = Self.activeSpaceSymbol != nil
        let copyManagedResolved = Self.copyManagedSpacesSymbol != nil
        let copySpacesResolved = Self.copySpacesForWindowsSymbol != nil
        let snapshot = managedSnapshot()
        let probeOK = !snapshot.spaces.isEmpty
            || !snapshot.activeByDisplay.isEmpty
            || !snapshot.orderedIDsByDisplay.isEmpty
        return HealthReport(
            symbols: [
                .init(symbol: "CoreGraphics.dlopen", resolved: handleResolved, role: .critical),
                .init(symbol: CGSSymbol.defaultConnection, resolved: connectionResolved, role: .critical),
                .init(symbol: CGSSymbol.getActiveSpace, resolved: getActiveResolved, role: .required),
                .init(symbol: CGSSymbol.copyManagedDisplaySpaces, resolved: copyManagedResolved, role: .required),
                .init(symbol: CGSSymbol.copySpacesForWindows, resolved: copySpacesResolved, role: .optional),
            ],
            payloadProbeSucceeded: probeOK
        )
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

/// Thread-safe short-TTL memoization cache for CGSCopySpacesForWindows results.
/// Reduces redundant IPC round-trips when the same window is resolved multiple
/// times within a brief window (e.g., filter + grouper, or rapid re-opens).
final class CGSSpacesCache {
    private let lock = NSLock()
    private var entries: [Int: (spaces: [Int], fetchedAt: Date)] = [:]
    private let ttl: TimeInterval = 3.0
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func resolved(windowID: Int) -> [Int]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[windowID] else { return nil }
        if entry.fetchedAt.timeIntervalSince(now()) < -ttl {
            entries.removeValue(forKey: windowID)
            return nil
        }
        return entry.spaces
    }

    func store(windowID: Int, spaces: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        entries[windowID] = (spaces: spaces, fetchedAt: now())
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
