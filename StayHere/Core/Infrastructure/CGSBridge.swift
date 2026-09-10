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

/// Abstraction over the short-TTL memoization cache used by
/// `CGSBridge.spacesForWindow`. Lets tests inject deterministic or no-op
/// caches and lets call sites scope cache lifetime/TTL to their own bridge.
/// Must remain public because it is exposed via CGSBridge.init parameter type;
/// callers should not depend on this protocol directly — use @testable import
/// for test injection only.
public protocol SpacesForWindowCaching {
    func resolved(windowID: Int) -> [Int]?
    func store(windowID: Int, spaces: [Int])
    func clear()
}

/// Abstraction over lazy dlopen/dlsym resolution of private CGS symbols.
/// Lets tests inject a deterministic resolver and eliminates hidden global
/// mutable state from the bridge.
/// Must remain public because it is exposed via CGSBridge.init parameter type;
/// callers should not depend on this protocol directly — use @testable import
/// for test injection only.
public protocol CGSSymbolResolving {
    func ensureHandle() -> UnsafeMutableRawPointer?
    func resolve<T>(_ name: String, as type: T.Type) -> T?
    func isResolved<T>(_ name: String, as type: T.Type) -> Bool
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

    private let spacesCache: any SpacesForWindowCaching
    private let symbolResolver: any CGSSymbolResolving

    public init(
        spacesCache: any SpacesForWindowCaching = CGSSpacesCache(),
        symbolResolver: any CGSSymbolResolving = CGSSymbolResolver()
    ) {
        self.spacesCache = spacesCache
        self.symbolResolver = symbolResolver
    }

    private var mainConn: MainConn? {
        symbolResolver.resolve(CGSSymbol.defaultConnection, as: MainConn.self)
            ?? symbolResolver.resolve(CGSSymbol.mainConnectionFallback, as: MainConn.self)
    }
    private var activeSpaceSymbol: GetActive? {
        symbolResolver.resolve(CGSSymbol.getActiveSpace, as: GetActive.self)
    }
    private var copyManagedSpacesSymbol: CopyManaged? {
        symbolResolver.resolve(CGSSymbol.copyManagedDisplaySpaces, as: CopyManaged.self)
    }
    private var copySpacesForWindowsSymbol: CopySpacesForWindows? {
        symbolResolver.resolve(CGSSymbol.copySpacesForWindows, as: CopySpacesForWindows.self)
    }

    /// Clears the memoization cache. Called when space-filtering settings change
    /// so stale CGS results are not served after invalidation.
    public func clearSpacesCache() {
        spacesCache.clear()
    }

    public func activeSpaceID() -> Int? {
        guard let main = mainConn,
              let getActive = activeSpaceSymbol else {
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
        guard let main = mainConn,
              let copyManaged = copyManagedSpacesSymbol,
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
        if let cached = spacesCache.resolved(windowID: windowID) {
            return cached
        }

        guard let main = mainConn,
              let copySpaces = copySpacesForWindowsSymbol else {
            return []
        }

        // 0x7 matches the common "all spaces" selector used in CGS prior art.
        let windowIDs: [NSNumber] = [NSNumber(value: windowID)]
        guard let raw = copySpaces(main(), 0x7, windowIDs as CFArray)?.takeRetainedValue() else {
            return []
        }

        if let ids = raw as? [NSNumber] {
            let spaces = ids.map(\.intValue)
            spacesCache.store(windowID: windowID, spaces: spaces)
            return spaces
        }
        return []
    }

    public func bridgeHealth() -> HealthReport {
        guard !RuntimeEnvironment.isAutomationSession else { return .notApplicable }

        // Actively attempt resolution of all symbols (triggers dlopen/dlsym).
        _ = symbolResolver.ensureHandle()
        let main = mainConn
        let getActive = activeSpaceSymbol
        let copyManaged = copyManagedSpacesSymbol
        _ = copySpacesForWindowsSymbol

        // Smoke-test resolved function pointers to validate unsafeBitCast results.
        var payloadProbeSucceeded = false
        if let main, let getActive {
            let connID = main()
            if connID != 0 {
                _ = getActive(connID)
                payloadProbeSucceeded = true
            }
        }
        if let main, let copyManaged {
            if let array = copyManaged(main())?.takeRetainedValue() as? [[String: Any]], !array.isEmpty {
                payloadProbeSucceeded = true
            }
        }

        // Read-only checks for reporting (isResolved has no side effects).
        let handleResolved = symbolResolver.ensureHandle() != nil
        let connectionResolved = symbolResolver.isResolved(CGSSymbol.defaultConnection, as: MainConn.self)
            || symbolResolver.isResolved(CGSSymbol.mainConnectionFallback, as: MainConn.self)
        let getActiveResolved = symbolResolver.isResolved(CGSSymbol.getActiveSpace, as: GetActive.self)
        let copyManagedResolved = symbolResolver.isResolved(CGSSymbol.copyManagedDisplaySpaces, as: CopyManaged.self)
        let copySpacesResolved = symbolResolver.isResolved(CGSSymbol.copySpacesForWindows, as: CopySpacesForWindows.self)

        return HealthReport(
            symbols: [
                .init(symbol: "CoreGraphics.dlopen", resolved: handleResolved, role: .critical),
                .init(symbol: CGSSymbol.defaultConnection, resolved: connectionResolved, role: .critical),
                .init(symbol: CGSSymbol.getActiveSpace, resolved: getActiveResolved, role: .required),
                .init(symbol: CGSSymbol.copyManagedDisplaySpaces, resolved: copyManagedResolved, role: .required),
                .init(symbol: CGSSymbol.copySpacesForWindows, resolved: copySpacesResolved, role: .optional),
            ],
            payloadProbeSucceeded: payloadProbeSucceeded
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

/// Lazily resolves the private CGS symbol surface. dlopen/dlsym is deferred
/// until first use so failures are observable via bridgeHealth() and
/// retryable (failed lookups are not cached). Thread-safe.
///
/// Conforms to @unchecked Sendable because all mutable state (handle,
/// handleFailed, resolvedSymbols) is exclusively accessed under an NSLock.
/// The lock serializes every read and write, making cross-concurrency-domain
/// access safe despite the absence of native Swift concurrency primitives.
public final class CGSSymbolResolver: CGSSymbolResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var handleFailed: Bool = false
    private var resolvedSymbols: [String: UnsafeMutableRawPointer] = [:]

    public init() {}

    public func ensureHandle() -> UnsafeMutableRawPointer? {
        lock.lock()
        defer { lock.unlock() }
        guard !RuntimeEnvironment.isAutomationSession else { return nil }
        if handle == nil && !handleFailed {
            handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
            if handle == nil {
                handleFailed = true
            }
        }
        return handle
    }

    public func resolve<T>(_ name: String, as _: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        if let sym = resolvedSymbols[name] {
            return unsafeBitCast(sym, to: T.self)
        }
        guard !handleFailed else { return nil }
        if handle == nil && !RuntimeEnvironment.isAutomationSession {
            handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
            if handle == nil {
                handleFailed = true
                return nil
            }
        }
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        resolvedSymbols[name] = sym
        return unsafeBitCast(sym, to: T.self)
    }

    /// Read-only check: returns true if the symbol has been successfully
    /// resolved and cached. Does NOT trigger resolution or have side effects.
    public func isResolved<T>(_ name: String, as _: T.Type) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolvedSymbols[name] != nil
    }
}

/// Thread-safe short-TTL memoization cache for CGSCopySpacesForWindows results.
/// Reduces redundant IPC round-trips when the same window is resolved multiple
/// times within a brief window (e.g., filter + grouper, or rapid re-opens).
/// Bounded by maxEntries with LRU eviction to prevent unbounded growth.
public final class CGSSpacesCache: SpacesForWindowCaching {
    private let lock = NSLock()
    private var entries: [Int: (spaces: [Int], fetchedAt: Date)] = [:]
    private let ttl: TimeInterval
    private let now: () -> Date
    private let maxEntries: Int

    public init(ttl: TimeInterval = 3.0, maxEntries: Int = 1024, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.maxEntries = maxEntries
        self.now = now
    }

    public func resolved(windowID: Int) -> [Int]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[windowID] else { return nil }
        if entry.fetchedAt.timeIntervalSince(now()) < -ttl {
            entries.removeValue(forKey: windowID)
            return nil
        }
        return entry.spaces
    }

    public func store(windowID: Int, spaces: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        if entries[windowID] != nil {
            entries[windowID] = (spaces: spaces, fetchedAt: now())
            return
        }
        while entries.count >= maxEntries {
            guard let oldestKey = entries.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key else { break }
            entries.removeValue(forKey: oldestKey)
        }
        entries[windowID] = (spaces: spaces, fetchedAt: now())
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
