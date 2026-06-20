import AppKit
import CoreGraphics

struct RawWindowInfo {
    let pid: pid_t
    let windowID: Int
    let layer: Int
    let workspace: Int?
    let isOnScreen: Bool
    let ownerName: String
    let windowName: String?
}

final class WindowEnumerator {
    typealias Provider = () -> [[String: Any]]?

    private let provider: Provider

    init(provider: @escaping Provider = WindowEnumerator.live) {
        self.provider = provider
    }

    func enumerate() -> [RawWindowInfo] {
        guard let raw = provider() else { return [] }
        return raw.compactMap { parse($0) }
    }

    private func parse(_ item: [String: Any]) -> RawWindowInfo? {
        guard let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
              let windowNumber = item[kCGWindowNumber as String] as? NSNumber,
              let layer = item[kCGWindowLayer as String] as? NSNumber else {
            return nil
        }

        return RawWindowInfo(
            pid: owner.int32Value,
            windowID: windowNumber.intValue,
            layer: layer.intValue,
            workspace: (item["kCGWindowWorkspace"] as? NSNumber)?.intValue,
            isOnScreen: (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            ownerName: (item[kCGWindowOwnerName as String] as? String) ?? "App",
            windowName: (item[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func live() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
    }
}
