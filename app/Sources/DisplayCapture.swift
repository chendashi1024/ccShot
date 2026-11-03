import AppKit
import ScreenCaptureKit

@MainActor enum DisplayCapture {
    struct Snapshot {
        let image: CGImage
        let targets: [WindowTarget]
    }
    enum CaptureError: Error { case permission, missing, unsupportedSize }

    static func capture(screen: NSScreen) async throws -> Snapshot {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permission }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { throw CaptureError.missing }
        let id = number.uint32Value
        let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where:{$0.displayID == id}) else { throw CaptureError.missing }
        let own = content.applications.filter{$0.processID == ProcessInfo.processInfo.processIdentifier}
        let filter = SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        // 逻辑显示尺寸可能只有Retina帧缓冲的一半；按系统捕获过滤器换算原生像素。
        let width = ceil(filter.contentRect.width*CGFloat(filter.pointPixelScale))
        let height = ceil(filter.contentRect.height*CGFloat(filter.pointPixelScale))
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 32768, height <= 32768, width*height <= 80_000_000 else { throw CaptureError.unsupportedSize }
        let config = SCStreamConfiguration(); config.width = Int(width); config.height = Int(height); config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        try Task.checkCancellation()
        guard NSScreen.screens.contains(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id}) else { throw CaptureError.missing }
        return Snapshot(image:image,targets:WindowCapture.targets(in:content,screen:screen))
    }
}
