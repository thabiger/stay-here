import Foundation
import Core

struct FilteredWindow {
    let windowID: Int
    let pid: pid_t
    let workspace: Int?
    let isOnScreen: Bool
    let ownerName: String
    let rawName: String?
    let application: (any WindowListApplication)?
}

struct FilterContext {
    let spaceID: Int
    let desktopNumber: Int?
}

final class WindowFilter {
    typealias RunningApplicationProvider = (pid_t) -> (any WindowListApplication)?

    private let settings: WindowSwitcherSettings
    private let runningApplicationProvider: RunningApplicationProvider
    private let spacesForWindow: (Int) -> [Int]

    init(
        settings: WindowSwitcherSettings,
        runningApplicationProvider: @escaping RunningApplicationProvider,
        spacesForWindow: @escaping (Int) -> [Int]
    ) {
        self.settings = settings
        self.runningApplicationProvider = runningApplicationProvider
        self.spacesForWindow = spacesForWindow
    }

    func filter(_ windows: [RawWindowInfo], in context: FilterContext) -> [FilteredWindow] {
        windows.compactMap { raw -> FilteredWindow? in
            guard raw.layer == 0 else { return nil }

            if let workspace = raw.workspace, let desktopNumber = context.desktopNumber {
                if workspace != desktopNumber { return nil }
            }

            if raw.workspace == nil {
                let spaceIDs = spacesForWindow(raw.windowID)
                guard spaceIDs.contains(context.spaceID) else { return nil }
            }

            let application = runningApplicationProvider(raw.pid)

            if application?.isHidden == true {
                if !settings.windowSwitcherShowHiddenWindows { return nil }
            } else if !raw.isOnScreen && !settings.windowSwitcherShowMinimizedWindows {
                return nil
            }

            return FilteredWindow(
                windowID: raw.windowID,
                pid: raw.pid,
                workspace: raw.workspace,
                isOnScreen: raw.isOnScreen,
                ownerName: raw.ownerName,
                rawName: raw.windowName,
                application: application
            )
        }
    }

    func filterForAllSpaces(_ windows: [RawWindowInfo], currentSpaceID: Int) -> [FilteredWindow] {
        windows.compactMap { raw -> FilteredWindow? in
            guard raw.layer == 0 else { return nil }

            let application = runningApplicationProvider(raw.pid)

            if application?.isHidden == true,
               !settings.windowSwitcherShowHiddenWindows {
                return nil
            }

            let isOnScreen = raw.isOnScreen
            if !isOnScreen && !settings.windowSwitcherShowMinimizedWindows {
                let spaceIDs = spacesForWindow(raw.windowID)
                let isOnCurrentSpace = spaceIDs.contains(currentSpaceID)
                if isOnCurrentSpace {
                    return nil
                }
            }

            return FilteredWindow(
                windowID: raw.windowID,
                pid: raw.pid,
                workspace: raw.workspace,
                isOnScreen: raw.isOnScreen,
                ownerName: raw.ownerName,
                rawName: raw.windowName,
                application: application
            )
        }
    }
}
