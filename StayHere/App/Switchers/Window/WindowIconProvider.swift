import AppKit
import UniformTypeIdentifiers

protocol WindowListApplication {
    var isHidden: Bool { get }
    var localizedName: String? { get }
    var bundleURL: URL? { get }
}

extension NSRunningApplication: WindowListApplication {}

final class WindowIconProvider {
    /// Thread-safe, size-limited icon cache. Static because callers
    /// (WindowListProviderTypes.liveIconProvider) instantiate a fresh
    /// WindowIconProvider per call; the cache must survive across instances
    /// and across the @MainActor inline path and Task.detached background path.
    static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256   // LRU eviction; memory-pressure eviction by NSCache
        return cache
    }()

    /// Sentinel key for the generic UTType.application fallback icon.
    private static let genericIconKey = "__stayhere_generic_application_icon__"
    private static let iconSize = NSSize(width: 18, height: 18)

    func icon(for application: (any WindowListApplication)?) -> NSImage {
        if let bundleURL = application?.bundleURL {
            return Self.cachedIcon(forKey: bundleURL.path) {
                Self.resized(NSWorkspace.shared.icon(forFile: bundleURL.path))
            }
        }
        return Self.cachedIcon(forKey: Self.genericIconKey) {
            Self.resized(NSWorkspace.shared.icon(for: UTType.application))
        }
    }

    private static func cachedIcon(forKey key: String, make: () -> NSImage) -> NSImage {
        let nsKey = key as NSString
        if let cached = iconCache.object(forKey: nsKey) {
            return cached
        }
        let icon = make()
        iconCache.setObject(icon, forKey: nsKey)
        return icon
    }

    /// Produce an 18x18 icon by drawing into a fresh 2x bitmap. Never mutates
    /// `icon.size` on any NSImage, so the shared cached instance is never
    /// mutated (also fixes the off-main NSImage mutation latent issue).
    private static func resized(_ icon: NSImage) -> NSImage {
        let scale: CGFloat = 2
        let pixelSize = NSSize(
            width: iconSize.width * scale,
            height: iconSize.height * scale
        )
        let resized = NSImage(size: iconSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return resized
        }
        rep.size = iconSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: iconSize))
        NSGraphicsContext.restoreGraphicsState()
        resized.addRepresentation(rep)
        return resized
    }
}
