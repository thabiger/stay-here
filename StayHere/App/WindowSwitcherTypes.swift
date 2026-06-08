import AppKit

struct WindowEntry {
    let windowID: Int
    let pid: pid_t
    let appName: String
    let windowTitle: String?
    let icon: NSImage
}

struct WindowSpaceContext {
    let spaceID: Int
    let desktopNumber: Int?
}
