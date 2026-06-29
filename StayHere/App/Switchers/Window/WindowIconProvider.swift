import AppKit
import UniformTypeIdentifiers

protocol WindowListApplication {
    var isHidden: Bool { get }
    var localizedName: String? { get }
    var bundleURL: URL? { get }
}

extension NSRunningApplication: WindowListApplication {}

final class WindowIconProvider {
    func icon(for application: (any WindowListApplication)?) -> NSImage {
        if let bundleURL = application?.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        let icon = NSWorkspace.shared.icon(for: UTType.application)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}
