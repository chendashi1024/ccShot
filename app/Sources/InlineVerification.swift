import AppKit

@MainActor enum InlineVerification {
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
