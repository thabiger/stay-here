import Foundation

enum SwitcherKind: Equatable {
    case any
    case space
    case window
    case allSpacesWindow

    init?(token: String) {
        switch token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-") {
        case "switcher", "switchers", "any":
            self = .any
        case "space", "spaces", "space-switcher", "spaces-switcher":
            self = .space
        case "window", "windows", "window-switcher", "windows-switcher":
            self = .window
        case "all-spaces-window", "all-windows", "allspaces", "all-spaces-window-switcher":
            self = .allSpacesWindow
        default:
            return nil
        }
    }
}

enum SwitcherAction: Equatable {
    case open
    case close
    case next
    case previous
    case commit
    case select
    case cancel

    init?(token: String) {
        switch token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-") {
        case "open", "show":
            self = .open
        case "close", "dismiss", "hide":
            self = .close
        case "next", "forward":
            self = .next
        case "previous", "prev", "back", "backward":
            self = .previous
        case "commit", "confirm":
            self = .commit
        case "select":
            self = .select
        case "cancel":
            self = .cancel
        default:
            return nil
        }
    }
}

struct SwitcherCommand: Equatable {
    let kind: SwitcherKind
    let action: SwitcherAction
    let index: Int?

    init(kind: SwitcherKind, action: SwitcherAction, index: Int? = nil) {
        self.kind = kind
        self.action = action
        self.index = index
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "stayhere" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        if let kind = Self.queryValue(named: "target", from: queryItems).flatMap(SwitcherKind.init),
           let action = Self.queryValue(named: "action", from: queryItems).flatMap(SwitcherAction.init),
           let index = Self.queryValue(named: "index", from: queryItems).flatMap(Self.parseIndex),
           Self.isSupported(kind: kind, action: action, index: index) {
            self.init(kind: kind, action: action, index: index)
            return
        }

        if let kind = Self.queryValue(named: "target", from: queryItems).flatMap(SwitcherKind.init),
           let action = Self.queryValue(named: "action", from: queryItems).flatMap(SwitcherAction.init),
           Self.isSupported(kind: kind, action: action, index: nil) {
            self.init(kind: kind, action: action)
            return
        }

        let host = (components?.host ?? "").lowercased()
        let pathComponents = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }

        if host == "switcher",
           let actionToken = pathComponents.first,
           let action = SwitcherAction(token: actionToken),
           pathComponents.count == 1,
           Self.isSupported(kind: .any, action: action, index: nil) {
            self.init(kind: .any, action: action)
            return
        }

        if host == "switcher",
           let actionToken = pathComponents.first,
           let action = SwitcherAction(token: actionToken),
           let indexToken = pathComponents.dropFirst().first,
           let index = Self.parseIndex(indexToken),
           pathComponents.count == 2,
           Self.isSupported(kind: .any, action: action, index: index) {
            self.init(kind: .any, action: action, index: index)
            return
        }

        if host == "switcher",
           let kindToken = pathComponents.first,
           let actionToken = pathComponents.dropFirst().first,
           let kind = SwitcherKind(token: kindToken),
           let action = SwitcherAction(token: actionToken),
           Self.isSupported(kind: kind, action: action, index: nil) {
            self.init(kind: kind, action: action)
            return
        }

        if let kind = SwitcherKind(token: host),
           let actionToken = pathComponents.first,
           let action = SwitcherAction(token: actionToken),
           Self.isSupported(kind: kind, action: action, index: nil) {
            self.init(kind: kind, action: action)
            return
        }

        return nil
    }

    private static func queryValue(named name: String, from items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private static func parseIndex(_ value: String) -> Int? {
        guard let index = Int(value), index > 0 else { return nil }
        return index
    }

    private static func isSupported(kind: SwitcherKind, action: SwitcherAction, index: Int?) -> Bool {
        switch (kind, action) {
        case (.space, .close), (.window, .close), (.allSpacesWindow, .close),
             (.space, .next), (.window, .next), (.allSpacesWindow, .next),
             (.space, .previous), (.window, .previous), (.allSpacesWindow, .previous),
             (.space, .commit), (.window, .commit), (.allSpacesWindow, .commit),
             (.space, .select), (.window, .select), (.allSpacesWindow, .select):
            return false
        case (.any, .select):
            return index != nil
        default:
            return index == nil
        }
    }
}
