import AppKit
import QuartzCore
import Darwin
import ScreenCaptureKit

@MainActor enum PerformanceVerification {
    private struct Fixture: Decodable {
        let id: String
        let category: String
        let condition: String
        let file: String
        let text: String
    }
    @MainActor private final class WeakWindow {
        weak var value: ImageWindow?
        weak var window: NSWindow?
        weak var canvas: AnnotationCanvas?
        weak var document: AnnotationDocument?
        init(_ value: ImageWindow) {self.value=value;window=value.window;canvas=value.canvas;document=value.annotationDocument}
        var survivors: [String:Int] {["controller":value == nil ? 0:1,"window":window == nil ? 0:1,"canvas":canvas == nil ? 0:1,"document":document == nil ? 0:1]}
    }
    private static func write(_ data: [String:Any],to path: String) throws {
        try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path),options:.atomic)
    }
    static func memory() -> [String:Any] {
        var value=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let status=withUnsafeMutablePointer(to:&value){ptr in
            ptr.withMemoryRebound(to:integer_t.self,capacity:Int(count)){task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)}
        }
        return ["valid":status==KERN_SUCCESS,"phys_footprint_bytes":value.phys_footprint,"resident_bytes":value.resident_size]
    }
    private static func processAgeMS() -> Double? {
        var info=proc_bsdinfo()
        let size=Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(getpid(),PROC_PIDTBSDINFO,0,&info,size)==size else { return nil }
        return (Date().timeIntervalSince1970-Double(info.pbi_start_tvsec)-Double(info.pbi_start_tvusec)/1_000_000)*1000
    }
    private static func image(_ fixture:Fixture,directory:String) throws -> CGImage {
        let url=URL(fileURLWithPath:directory).appendingPathComponent(fixture.file)
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }
    private static func englishImage() -> CGImage {
        let context=CGContext(data:nil,width:1920,height:460,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:1920,height:460))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        let attributes: [NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.black]
        ("Local screenshots stay on your Mac." as NSString).draw(at:CGPoint(x:64,y:330),withAttributes:attributes)
        ("Select text, add an arrow, then copy." as NSString).draw(at:CGPoint(x:64,y:220),withAttributes:attributes)
        NSGraphicsContext.restoreGraphicsState();return context.makeImage()!
    }
    private static func consume(_ image:CGImage,id:String,expected:String,preferences:AppPreferences) async -> ([String:Any],WeakWindow) {
        let started=ProcessInfo.processInfo.systemUptime
        var editor:ImageWindow?=ImageWindow(image:image,pinned:false,preferences:preferences)
        let weak=WeakWindow(editor!)
        let created=ProcessInfo.processInfo.systemUptime
        await editor!.recognitionForVerification?.value
        let analyzed=ProcessInfo.processInfo.systemUptime
        let text=editor!.recognizedTextForVerification
        editor!.selectAll(nil)
        let selectable = !text.isEmpty && editor!.selectedTextForVerification==text
        editor!.window?.displayIfNeeded();CATransaction.flush()
        let elapsed=(ProcessInfo.processInfo.systemUptime-started)*1000
        let row: [String:Any]=["id":id,"latency_ms":elapsed,"window_init_ms":(created-started)*1000,"analysis_wait_ms":(analyzed-created)*1000,"selection_and_frame_ms":elapsed-(analyzed-started)*1000,"text":text,"expected":expected,"text_selectable":selectable,"width":image.width,"height":image.height,"memory_with_editor":memory()]
        editor!.close();editor=nil
        return (row,weak)
    }
    static func run(mode:String,reportPath:String,fixtureDirectory:String,controller:AppController,displayHost:String?) async -> Int32 {
        guard !FileManager.default.fileExists(atPath:reportPath) else {return 2}
        let suite="com.ccshot.performance.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:suite)!
        defer {store.removePersistentDomain(forName:suite)}
        do {
            if mode=="startup" {
                let ready=controller.performanceReadyState()
                let readyAge=processAgeMS()
                try await Task.sleep(for:.seconds(2))
                try write(["completed":true,"mode":mode,"process_start_to_ready_ms":readyAge.map{$0 as Any} ?? NSNull(),"ready_state":ready,"idle_after_2s":memory(),"scope":"内核进程开始时间至菜单/热键注册与AppKit提交；不含实体按键和屏幕实际呈现延迟。进程重启，未清系统缓存。"],to:reportPath)
                return ready["ready"] as? Bool == true && readyAge != nil ? 0:1
            }
            if mode=="capture" {
                guard CGPreflightScreenCaptureAccess(),let displayHost,FileManager.default.isExecutableFile(atPath:displayHost) else {throw CocoaError(.featureUnsupported)}
                let ready=URL(fileURLWithPath:reportPath).deletingPathExtension().appendingPathExtension("ready.json")
                let host=Process();host.executableURL=URL(fileURLWithPath:displayHost)
                host.arguments=[URL(fileURLWithPath:fixtureDirectory).appendingPathComponent("01-01.png").path,ready.path]
                host.standardOutput=FileHandle.nullDevice;host.standardError=FileHandle.nullDevice
                defer {controller.performanceCloseSelection();if host.isRunning {host.terminate()};try? FileManager.default.removeItem(at:ready)}
                try host.run()
                let deadline=ProcessInfo.processInfo.systemUptime+5
                while host.isRunning && !FileManager.default.fileExists(atPath:ready.path) && ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(for:.milliseconds(20))}
                guard host.isRunning,let hostInfo=(try? JSONSerialization.jsonObject(with:Data(contentsOf:ready))) as? [String:Any],let surfaces=hostInfo["screens"] as? [[String:Any]],surfaces.count==NSScreen.screens.count else {throw CocoaError(.featureUnsupported)}
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard surfaces.allSatisfy({surface in
                    guard let id=(surface["id"] as? NSNumber)?.uint32Value else {return false}
                    return content.windows.contains{$0.windowID==id && $0.owningApplication?.processID==host.processIdentifier}
                }) else {throw CocoaError(.featureUnsupported)}
                var rows:[[String:Any]]=[]
                for index in 0...200 {
                    guard host.isRunning else {throw CocoaError(.featureUnsupported)}
                    let started=ProcessInfo.processInfo.systemUptime,expires=started+8
                    controller.capture()
                    var observation:[String:Any]?
                    while ProcessInfo.processInfo.systemUptime<expires {
                        if NSApp.modalWindow != nil {NSApp.abortModal();throw CocoaError(.featureUnsupported)}
                        if let value=controller.performanceSelectionObservation(),value["ready"] as? Bool==true {observation=value;break}
                        try await Task.sleep(for:.milliseconds(1))
                    }
                    guard host.isRunning,let value=observation,value["fixture_corners_valid"] as? Bool==true,let submitted=value["submitted_uptime"] as? Double else {throw CocoaError(.featureUnsupported)}
                    rows.append(["index":index,"priming":index==0,"action_to_submitted_frame_ms":(submitted-started)*1000,"width":value["width"]!,"height":value["height"]!])
                    controller.performanceCloseSelection()
                    guard controller.performanceSelectionObservation()==nil else {throw CocoaError(.featureUnsupported)}
                    try write(["completed":false,"mode":mode,"results":rows],to:reportPath)
                }
                try await Task.sleep(for:.seconds(2))
                try write(["completed":true,"mode":mode,"results":rows,"selection_windows_after":NSApp.windows.filter{$0 is SelectionWindow && $0.isVisible}.count,"memory_after_2s":memory(),"scope":"真实AppController.capture入口，200次整屏截图遮罩打开/关闭；自制独立进程覆盖屏幕，首个预热样本保留。动作入口至可交互NSWindow提交，不含实体全局键/物理屏幕显示。持续时间不是30分钟；不存截图/识字文本，不操作剪贴板。"],to:reportPath)
                return 0
            }
            let manifest=URL(fileURLWithPath:fixtureDirectory).appendingPathComponent("manifest.json")
            let fixtures=try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:manifest))
            let preferences=AppPreferences(store:store)
            if ["first-chinese","first-english","first-mixed"].contains(mode) {
                let id=mode=="first-chinese" ? "01-01":"03-01"
                var input:CGImage,expected:String
                if mode=="first-english" {
                    input=englishImage();expected="Local screenshots stay on your Mac.\nSelect text, add an arrow, then copy."
                    if let png=ImageEncoding.data(input,type:.png) {try png.write(to:URL(fileURLWithPath:reportPath).deletingPathExtension().appendingPathExtension("png"),options:.atomic)}
                } else {
                    guard let fixture=fixtures.first(where:{$0.id==id}) else {throw CocoaError(.fileReadCorruptFile)}
                    input=try image(fixture,directory:fixtureDirectory);expected=fixture.text
                }
                let (row,weak)=await consume(input,id:mode,expected:expected,preferences:preferences)
                try await Task.sleep(for:.milliseconds(100))
                try write(["completed":true,"mode":mode,"result":row,"closed_controller_released":weak.value==nil,"windows_after_close":NSApp.windows.filter{$0.isVisible && $0.level == .normal}.count,"memory_after_close":memory(),"scope":"新进程首次分析，系统框架缓存未清；从编辑窗口创建到文字可全选及AppKit提交，非实体拖选时延。"],to:reportPath)
                return row["text_selectable"] as? Bool == true && weak.value==nil ? 0:1
            }
            guard mode=="matrix" else {throw CocoaError(.featureUnsupported)}
            var rows: [[String:Any]]=[],weakWindows:[WeakWindow]=[]
            let baseline=memory()
            for repetition in 1...3 {
                for fixture in fixtures {
                    let (value,weak)=await consume(try image(fixture,directory:fixtureDirectory),id:fixture.id,expected:fixture.text,preferences:preferences)
                    var row=value;row["category"]=fixture.category;row["condition"]=fixture.condition;row["repetition"]=repetition;row["process_first_analysis"]=rows.isEmpty
                    rows.append(row);weakWindows.append(weak)
                    // 原始记录逐次落盘，崩溃也保留已完成的数据，不改变识字计时边界。
                    try write(["completed":false,"mode":mode,"results":rows],to:reportPath)
                }
            }
            try await Task.sleep(for:.seconds(2))
            let idleAfterCorpus=memory(),corpusSurvivors=weakWindows.filter{$0.value != nil}.count
            var pins:[ImageWindow]=[],pinWeak:[WeakWindow]=[],pinMemory:[[String:Any]]=[]
            guard let first=fixtures.first(where:{$0.id=="01-01"}) else {throw CocoaError(.fileReadCorruptFile)}
            for number in 1...10 {
                // 每张钉图独立位图，避免同一CGImage共享让内存结果偏低。
                let base=try image(first,directory:fixtureDirectory)
                guard let copied=AnnotationRenderer.render(base:base,objects:[]) else {throw CocoaError(.coderInvalidValue)}
                let pin=ImageWindow(image:copied,pinned:true,preferences:preferences);pins.append(pin);pinWeak.append(WeakWindow(pin))
                await pin.recognitionForVerification?.value
                if [1,5,10].contains(number) {try await Task.sleep(for:.seconds(1));pinMemory.append(["pins":number,"memory":memory()])}
            }
            for pin in pins {pin.close()};pins.removeAll()
            try await Task.sleep(for:.seconds(2))
            let memoryAfter2s=memory()
            var delayed:[[String:Any]]=[["seconds_after_close":2,"memory":memoryAfter2s]]
            try await Task.sleep(for:.seconds(8));delayed.append(["seconds_after_close":10,"memory":memory()])
            try await Task.sleep(for:.seconds(20));delayed.append(["seconds_after_close":30,"memory":memory()])
            let survivors=pinWeak.filter{$0.value != nil}.count
            let completed=rows.count==fixtures.count*3 && rows.allSatisfy{$0["text_selectable"] as? Bool==true} && corpusSurvivors==0 && survivors==0
            try write(["completed":true,"checks_passed":completed,"mode":mode,"results":rows,"idle_before_ocr":baseline,"idle_after_corpus_2s":idleAfterCorpus,"corpus_controller_survivors":corpusSurvivors,"pin_memory":pinMemory,"idle_after_pins_closed_2s":memoryAfter2s,"after_close_samples":delayed,"pin_object_survivors":pinWeak.map(\.survivors),"corpus_object_survivors":weakWindows.map(\.survivors),"nsapp_windows_including_hidden":NSApp.windows.count,"pin_controller_survivors":survivors,"visible_normal_or_floating_windows":NSApp.windows.filter{$0.isVisible && ($0.level == .normal || $0.level == .floating)}.count,"scope":"32张固定自制图各3次编辑态分析、10张独立位图钉图；不是200次真实截图或30分钟稳定性验收。未操作剪贴板。"],to:reportPath)
            return completed ? 0:1
        } catch {
            var partial=((try? Data(contentsOf:URL(fileURLWithPath:reportPath))).flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any]) ?? ["mode":mode]
            partial["completed"]=false;partial["error"]="measurement_failed"
            try? write(partial,to:reportPath)
            return 1
        }
    }
}
