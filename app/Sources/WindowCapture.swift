import AppKit
import ScreenCaptureKit

@MainActor enum WindowCapture {
    struct Snapshot {let image:CGImage;let quartzFrame:CGRect}
    enum CaptureError: Error { case permission, missing, unsupportedSize }

    static func targets(in content: SCShareableContent, screen: NSScreen) -> [WindowTarget] {
        let allowed = Set(content.windows.filter { $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }.map(\.windowID))
        guard let primary = NSScreen.screens.first,
              let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return ordered.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? NSNumber, allowed.contains(id.uint32Value),
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let values = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: values),
                  let rect = WindowTarget.localRect(quartzFrame: quartz, screenFrame: screen.frame, primaryTop: primary.frame.maxY) else { return nil }
            return WindowTarget(id: id.uint32Value, ownerPID: pid.int32Value, rect: rect)
        }
    }
    static func capture(id:UInt32,ownerPID:Int32) async throws -> CGImage {
        try await captureSnapshot(id:id,ownerPID:ownerPID).image
    }
    static func captureSnapshot(id: UInt32, ownerPID: Int32) async throws -> Snapshot {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let target = content.windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == ownerPID && $0.isOnScreen }) else { throw CaptureError.missing }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let scale = CGFloat(filter.pointPixelScale)
        let width = ceil(filter.contentRect.width * scale)
        let height = ceil(filter.contentRect.height * scale)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 32768, height <= 32768, width * height <= 80_000_000 else { throw CaptureError.unsupportedSize }
        let config = SCStreamConfiguration()
        config.width = Int(width); config.height = Int(height)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        return Snapshot(image:image,quartzFrame:target.frame)
    }
}
