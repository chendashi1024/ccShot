import AppKit

@MainActor enum PinVerification {
    private static var preview:ImageWindow?
    private static var backdrop:NSWindow?
    static func run(image:CGImage,reportPath:String,keepPreview:Bool=false) async -> Bool {
        let suite="com.ccshot.pin-check.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:suite)!
        let screen=NSScreen.screens.first
        if keepPreview,let screen {
            let background=AnnotationWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            background.isReleasedWhenClosed=false;background.backgroundColor=NSColor(srgbRed:0.86,green:0.89,blue:0.86,alpha:1);background.hasShadow=false
            background.orderFrontRegardless();backdrop=background
        }
        let frame=screen.map {PinLayout.frame(pixels:CGSize(width:image.width,height:image.height),scale:$0.backingScaleFactor,visible:$0.visibleFrame)}
        let pin=ImageWindow(annotationDocument:AnnotationDocument(image:image),pinned:true,preferences:AppPreferences(store:store),pinFrame:frame)
        await pin.recognitionForVerification?.value
        let checks=await pin.pinLayoutChecks()
        let passed = !checks.isEmpty && checks.values.allSatisfy{$0}
        let value:[String:Any]=["fixture_only":true,"checks":checks,"passed":passed,"clipboard_written":false]
        guard let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]),(try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic)) != nil else {pin.close();return false}
        if keepPreview {
            preview=pin;pin.onClose={store.removePersistentDomain(forName:suite);preview=nil;backdrop?.close();backdrop=nil}
        } else {pin.close();store.removePersistentDomain(forName:suite)}
        return passed
    }
}
