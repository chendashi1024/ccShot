import AppKit

@MainActor enum InlineVerification {
    private static var previewWindow:ImageWindow?
    static func runWindow(reportPath:String,preview:Bool=false) async -> Bool {
        guard let screen=NSScreen.main,let windowContext=CGContext(data:nil,width:800,height:500,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),
              let backgroundContext=CGContext(data:nil,width:Int(screen.frame.width),height:Int(screen.frame.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return false}
        windowContext.setFillColor(NSColor.white.cgColor);windowContext.fill(CGRect(x:0,y:0,width:800,height:500))
        windowContext.setFillColor(NSColor.red.cgColor);windowContext.fill(CGRect(x:0,y:0,width:120,height:500))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:windowContext,flipped:false)
        ("窗口原位编辑" as NSString).draw(at:CGPoint(x:150,y:380),withAttributes:[.font:NSFont.systemFont(ofSize:32,weight:.semibold),.foregroundColor:NSColor.black])
        ("可见内容保持原位，输出保留完整窗口。" as NSString).draw(at:CGPoint(x:150,y:300),withAttributes:[.font:NSFont.systemFont(ofSize:24),.foregroundColor:NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        backgroundContext.setFillColor(NSColor(srgbRed:0.82,green:0.86,blue:0.83,alpha:1).cgColor);backgroundContext.fill(CGRect(origin:.zero,size:screen.frame.size))
        guard let image=windowContext.makeImage(),let background=backgroundContext.makeImage() else {return false}
        let region=CGRect(x:-120,y:min(300,screen.frame.height-500),width:800,height:500)
        let presentation=ScreenshotPresentation(background:background,screenFrame:screen.frame,region:region,displayID:0,allowsAdjustment:false)
        let suite="com.ccshot.window-inline-check.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:suite)!
        let editor=ImageWindow(annotationDocument:AnnotationDocument(image:image),pinned:false,preferences:AppPreferences(store:store),screenshot:presentation)
        await editor.recognitionForVerification?.value
        let checks=editor.windowCaptureLayoutChecks(region:region,pixels:CGSize(width:800,height:500))
        let passed=checks.values.allSatisfy{$0} && !checks.isEmpty
        let payload:[String:Any]=["fixture_only":true,"actual_system_window_capture":false,"checks":checks,"passed":passed,"hidden_left_red_pixels_preserved":editor.stableImage().flatMap {PixelSampler.color(in:$0,x:20,y:20)?.hex} == "#FF0000"]
        guard let data=try? JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys]),(try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic)) != nil else {editor.close();store.removePersistentDomain(forName:suite);return false}
        if preview {previewWindow=editor;editor.onClose={store.removePersistentDomain(forName:suite);previewWindow=nil}} else {editor.close();store.removePersistentDomain(forName:suite)}
        return passed && (payload["hidden_left_red_pixels_preserved"] as? Bool == true)
    }
    static func run(reportPath:String) async -> Bool {
        let suite="com.ccshot.inline-check.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:suite)!
        defer {store.removePersistentDomain(forName:suite)}
        guard let c=CGContext(data:nil,width:1440,height:900,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return false}
        c.setFillColor(NSColor.gray.cgColor);c.fill(CGRect(x:0,y:0,width:1440,height:900))
        c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:362,y:280,width:716,height:450))
        c.setFillColor(NSColor.red.cgColor);c.fill(CGRect(x:380,y:300,width:25,height:30))
        guard let background=c.makeImage(),let crop=background.cropping(to:CGRect(x:362,y:170,width:716,height:450)) else {return false}
        let presentation=ScreenshotPresentation(background:background,screenFrame:CGRect(x:0,y:0,width:1440,height:900),region:CGRect(x:362,y:280,width:716,height:450),displayID:0,allowsAdjustment:true)
        let editor=ImageWindow(annotationDocument:AnnotationDocument(image:crop),pinned:false,preferences:AppPreferences(store:store),screenshot:presentation)
        defer {editor.close()}
        await editor.recognitionForVerification?.value
        let checks=editor.inlineLayoutChecks()
        let payload:[String:Any]=["schema":"ccshot.inline-editor.v1","checks":checks,"passed":!checks.isEmpty && checks.values.allSatisfy{$0},"clipboard_written":false,"system_input_method_verified":false]
        guard let data=try? JSONSerialization.data(withJSONObject:payload,options:[.prettyPrinted,.sortedKeys]),(try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic)) != nil else {return false}
        return !checks.isEmpty && checks.values.allSatisfy{$0}
    }
}
