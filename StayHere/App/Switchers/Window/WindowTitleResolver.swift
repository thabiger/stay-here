import ApplicationServices

typealias AccessibilityWindowTitlesProvider = (pid_t) -> [Int: String]

struct WindowWithTitle {
    let windowID: Int
    let pid: pid_t
    let appName: String
    let windowTitle: String?
}

final class WindowTitleResolver {
    typealias TitleProvider = (pid_t) -> [Int: String]

    private let titleProvider: TitleProvider

    init(titleProvider: @escaping TitleProvider = WindowTitleResolver.live) {
        self.titleProvider = titleProvider
    }

    func resolveTitles(
        for windows: [FilteredWindow],
        fallbackNameProvider: (pid_t) -> String?
    ) -> [WindowWithTitle] {
        var accessibilityTitleCache: [pid_t: [Int: String]] = [:]

        return windows.map { filtered in
            let appName = filtered.application?.localizedName
                ?? filtered.ownerName

            let windowTitle = title(for: filtered, cache: &accessibilityTitleCache)
                ?? fallbackNameProvider(filtered.pid)

            return WindowWithTitle(
                windowID: filtered.windowID,
                pid: filtered.pid,
                appName: appName,
                windowTitle: windowTitle
            )
        }
    }

    private func title(for window: FilteredWindow, cache: inout [pid_t: [Int: String]]) -> String? {
        if let rawName = window.rawName, !rawName.isEmpty {
            return rawName
        }

        if let cached = cache[window.pid] {
            return cached[window.windowID]
        }

        let titles = titleProvider(window.pid)
        cache[window.pid] = titles
        return titles[window.windowID]
    }

    static func live(pid: pid_t) -> [Int: String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return [:]
        }

        var titles: [Int: String] = [:]
        for window in windows {
            var numberRef: CFTypeRef?
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberRef) == .success,
                  let number = numberRef as? NSNumber,
                  AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            titles[number.intValue] = trimmed
        }
        return titles
    }
}
