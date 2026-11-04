import AppKit
import ScreenCaptureKit

// 仅捕获指定的本项目QA进程；过滤器不包含用户桌面和其他应用。
@main struct PinWindowGroupCapture {
    @MainActor static func main() async {
        let args=CommandLine.arguments
        guard args.count==3,let pid=Int32(args[1]),CGPreflightScreenCaptureAccess(),let screen=NSScreen.main,
              let displayID=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {exit(2)}
        do {
            let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
            guard let app=content.applications.first(where:{$0.processID==pid && $0.bundleIdentifier=="com.ccshot.pin-check"}),
                  let display=content.displays.first(where:{$0.displayID==displayID}) else {exit(2)}
            let filter=SCContentFilter(display:display,including:[app],exceptingWindows:[])
            let config=SCStreamConfiguration();config.width=Int(ceil(filter.contentRect.width*CGFloat(filter.pointPixelScale)));config.height=Int(ceil(filter.contentRect.height*CGFloat(filter.pointPixelScale)));config.showsCursor=false
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            guard let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {exit(1)}
            try data.write(to:URL(fileURLWithPath:args[2]),options:.atomic)
        } catch {print("QA窗口组截图失败");exit(1)}
    }
}
