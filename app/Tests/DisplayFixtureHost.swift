import AppKit
import QuartzCore

@MainActor final class FixtureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender:Any?) {NSApp.terminate(nil)}
}

@MainActor final class DisplayFixtureView: NSView {
    let fixture: CGImage
    init(fixture: CGImage,frame: CGRect) { self.fixture=fixture;super.init(frame:frame) }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context=NSGraphicsContext.current?.cgContext else{return}
        context.setFillColor(NSColor.white.cgColor);context.fill(bounds)
        let edge: CGFloat=50
        for (color,rect) in [(NSColor.red,CGRect(x:0,y:0,width:edge,height:edge)),(.green,CGRect(x:bounds.maxX-edge,y:0,width:edge,height:edge)),(.blue,CGRect(x:0,y:bounds.maxY-edge,width:edge,height:edge)),(.yellow,CGRect(x:bounds.maxX-edge,y:bounds.maxY-edge,width:edge,height:edge))] {
            context.setFillColor(color.cgColor);context.fill(rect)
        }
        let width=min(bounds.width-160,1000)
        let height=width*CGFloat(fixture.height)/CGFloat(fixture.width)
        context.interpolationQuality = .high
        context.draw(fixture,in:CGRect(x:(bounds.width-width)/2,y:(bounds.height-height)/2,width:width,height:height))
    }
}

@MainActor final class DisplayFixtureHost: NSObject, NSApplicationDelegate {
    var windows: [NSWindow]=[]
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args=CommandLine.arguments
        guard args.count==3,let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:args[1]) as CFURL,nil),let fixture=CGImageSourceCreateImageAtIndex(source,0,nil) else { exit(2) }
        var rows: [[String:Any]]=[]
        for (index,screen) in NSScreen.screens.enumerated() {
            let window=FixtureWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.isOpaque=true;window.hasShadow=false
            window.level=NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue-1)
            window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            window.contentView=DisplayFixtureView(fixture:fixture,frame:CGRect(origin:.zero,size:screen.frame.size))
            window.setFrame(screen.frame,display:true);window.orderFrontRegardless();window.display()
            windows.append(window)
            rows.append(["index":index,"id":window.windowNumber,"frame":[window.frame.minX,window.frame.minY,window.frame.width,window.frame.height]])
        }
        CATransaction.flush()
        let data=try! JSONSerialization.data(withJSONObject:["pid":ProcessInfo.processInfo.processIdentifier,"screens":rows],options:[.prettyPrinted,.sortedKeys])
        try! data.write(to:URL(fileURLWithPath:args[2]),options:.atomic)
        // 超时关闭自己的覆盖窗口，避免测试进程退出后留在屏幕上。
        DispatchQueue.main.asyncAfter(deadline:.now()+90){NSApp.terminate(nil)}
    }
}
@main struct FixtureMain {
    @MainActor static func main(){let app=NSApplication.shared;let host=DisplayFixtureHost();app.delegate=host;withExtendedLifetime(host){app.run()}}
}
