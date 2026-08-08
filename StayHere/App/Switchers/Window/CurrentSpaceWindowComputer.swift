import AppKit
import Core

/// Snapshot of main-actor state needed to compute the current-space window
/// list off the main thread.
struct CurrentSpaceWindowComputeContext: Sendable {
    let spaceID: Int
    let desktopNumber: Int?
    /// Settings snapshotted on the main actor so the background path never
    /// reads the shared mutable `WindowFilter.settings` reference.
    let showHiddenWindows: Bool
    let showMinimizedWindows: Bool
}

extension CurrentSpaceWindowComputer: @unchecked Sendable {}

/// Non-isolated computer. Sendability contract — why `@unchecked` is safe:
///
/// Isolation guarantees: the struct is constructed on the MainActor inside
/// `WindowListProvider.makeCurrentSpaceComputer` (WindowListProvider.swift:
/// 176–200), is never mutated after init (every member is an immutable
/// `let`), and is consumed by exactly ONE `Task.detached` per refresh —
/// instances are never shared between tasks or threads.
///
/// Member-by-member:
/// - `context` (`CurrentSpaceWindowComputeContext`): genuinely `Sendable`
///   value snapshot (Int / Int? / Bool) captured on the main actor — the
///   settings booleans are snapshotted at construction, so the background
///   path never reads the shared mutable `WindowFilter.settings`.
/// - `enumerator` (`WindowEnumerator`, final class): immutable; the only
///   method called is `enumerate()`, which reads its private provider
///   closure and parses the result; no mutable state is touched.
/// - `filter` (`WindowFilter`, final class): `compute()` calls ONLY the
///   parameterized overload with the snapshotted booleans
///   (CurrentSpaceWindowComputer.swift:30–35), so the mutable `settings`
///   reference held by the filter is never dereferenced off-main; its
///   `runningApplicationProvider`/`spacesForWindow` closures execute only
///   inside `filter(...)` during `compute()`.
/// - `titleResolver` (`WindowTitleResolver`, final class): all AX traffic
///   is serialized through its private serial `axQueue`
///   (WindowTitleResolver.swift:17); `resolveTitles` runs only from
///   `compute()`.
/// - `iconProvider` / `spacesForWindow` closures: invoked only from
///   `compute()` on the detached thread; their captures (cgsBridge, icon
///   provider) are used identically by the proven all-spaces path.
///
/// The dependency classes/closures cannot be statically verified as
/// Sendable (shared with the pre-existing all-spaces pipeline), hence
/// `@unchecked`; the runtime contract above is what makes crossing the
/// actor boundary safe.
struct CurrentSpaceWindowComputer {
    let enumerator: WindowEnumerator
    let filter: WindowFilter
    let titleResolver: WindowTitleResolver
    let iconProvider: WindowListProviderTypes.IconProvider
    let spacesForWindow: (Int) -> [Int]
    let context: CurrentSpaceWindowComputeContext

    func compute() -> [WindowEntry] {
        let rawWindows = enumerator.enumerate()
        let filtered = filter.filter(
            rawWindows,
            in: FilterContext(spaceID: context.spaceID, desktopNumber: context.desktopNumber),
            showHiddenWindows: context.showHiddenWindows,
            showMinimizedWindows: context.showMinimizedWindows
        )
        let withTitles = titleResolver.resolveTitles(for: filtered) { _ in nil }
        return withTitles.map {
            WindowEntry(
                windowID: $0.windowID,
                pid: $0.pid,
                appName: $0.appName,
                windowTitle: $0.windowTitle,
                icon: iconProvider($0.application)
            )
        }
    }
}
