import AppKit
import ScreenCaptureKit
import QuartzCore

@MainActor enum DisplayVerification {
    static func run(fixture: String, host: String, reportPath: String) async -> Int32 {
        let reportURL=URL(fileURLWithPath:reportPath)
        func write(_ value: [String:Any]) { if let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:reportURL,options:.atomic) } }
        guard CGPreflightScreenCaptureAccess() else { write(["passed":false,"status":"skipped","reason":"existing_permission_missing"]);return 2 }
        guard FileManager.default.isExecutableFile(atPath:host) else { write(["passed":false,"status":"skipped","reason":"fixture_host_missing"]);return 2 }
        let ready=reportURL.deletingLastPathComponent().appendingPathComponent("display-ready-\(UUID().uuidString).json")
        let process=Process();process.executableURL=URL(fileURLWithPath:host);process.arguments=[fixture,ready.path]
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        defer { if process.isRunning {process.terminate()};try? FileManager.default.removeItem(at:ready) }
        do { try process.run() } catch { write(["passed":false,"status":"host_start_failed"]);return 1 }
        let deadline=ProcessInfo.processInfo.systemUptime+5
        while process.isRunning && !FileManager.default.fileExists(atPath:ready.path) && ProcessInfo.processInfo.systemUptime<deadline { try? await Task.sleep(for:.milliseconds(50)) }
        guard process.isRunning,let data=try? Data(contentsOf:ready),let info=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let hosts=info["screens"] as? [[String:Any]],hosts.count==NSScreen.screens.count else { write(["passed":false,"status":"host_not_ready"]);return 1 }
        let screens=NSScreen.screens
        let suite="com.ccshot.display-check.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        var checks: [String:Bool]=[:],rows: [[String:Any]]=[]
        if let first=screens.first {
            let cancelled=Task {try await DisplayCapture.capture(screen:first)};cancelled.cancel()
            do {_ = try await cancelled.value;checks["cancelled_capture_rejected"]=false}
            catch is CancellationError {checks["cancelled_capture_rejected"]=true}
            catch {checks["cancelled_capture_rejected"]=false}
        }
        for (index,screen) in screens.enumerated() {
            let prefix="screen_\(index)"
            let screenID=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
            // 用本应用的紫色窗口验证生产截图确实排除了自身窗口。
            let proof=NSWindow(contentRect:CGRect(x:screen.frame.midX-100,y:screen.frame.minY+100,width:200,height:100),styleMask:.borderless,backing:.buffered,defer:false)
            proof.isReleasedWhenClosed=false;proof.isOpaque=true;proof.backgroundColor = .magenta;proof.hasShadow=false
            proof.level=NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue+1)
            proof.orderFrontRegardless();proof.display();CATransaction.flush()
            defer { proof.close() }
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard process.isRunning,let hostID=(hosts[index]["id"] as? NSNumber)?.uint32Value,
                      let target=content.windows.first(where:{$0.windowID==hostID && $0.owningApplication?.processID==process.processIdentifier}),
                      let primary=screens.first,let local=WindowTarget.localRect(quartzFrame:target.frame,screenFrame:screen.frame,primaryTop:primary.frame.maxY),local==CGRect(origin:.zero,size:screen.frame.size) else { throw DisplayCapture.CaptureError.missing }
                let started=ProcessInfo.processInfo.systemUptime
                var snapshot: DisplayCapture.Snapshot!
                var cornerOK=false,attempts=0
                // AppKit刷新与系统合成不同步时，仅重取同一个仍存活的自制样本。
                for attempt in 1...3 {
                    attempts=attempt;snapshot=try await DisplayCapture.capture(screen:screen)
                    let image=snapshot.image,sx=CGFloat(image.width)/screen.frame.width,sy=CGFloat(image.height)/screen.frame.height
                    func pixel(_ x: CGFloat,_ y: CGFloat)->SampledColor? {PixelSampler.color(in:image,x:Int(x*sx),y:image.height-1-Int(y*sy))}
                    let a=pixel(25,25),b=pixel(screen.frame.width-25,25),c=pixel(25,screen.frame.height-25),d=pixel(screen.frame.width-25,screen.frame.height-25)
                    cornerOK=(a.map{$0.red>180 && $0.green<130 && $0.blue<130} ?? false) && (b.map{$0.green>180 && $0.red<130 && $0.blue<130} ?? false) && (c.map{$0.blue>180 && $0.red<130 && $0.green<130} ?? false) && (d.map{$0.red>180 && $0.green>180 && $0.blue<130} ?? false)
                    if cornerOK {break};try await Task.sleep(for:.milliseconds(200))
                }
                let nativeMode=CGDisplayCopyDisplayMode(screenID)!
                let nativeDisplay=content.displays.first(where:{$0.displayID==screenID})!
                let nativeFilter=SCContentFilter(display:nativeDisplay,excludingApplications:[],exceptingWindows:[])
                let image=snapshot.image,elapsed=(ProcessInfo.processInfo.systemUptime-started)*1000
                let sx=CGFloat(image.width)/screen.frame.width,sy=CGFloat(image.height)/screen.frame.height
                let uncovered=PixelSampler.color(in:image,x:Int(screen.frame.width/2*sx),y:image.height-1-Int(150*sy))
                checks[prefix+"_four_corners_and_orientation"]=cornerOK
                checks[prefix+"_own_visible_window_excluded"]=uncovered.map{$0.red>245 && $0.green>245 && $0.blue>245} ?? false
                checks[prefix+"_native_display_resolution"]=image.width==nativeMode.pixelWidth && image.height==nativeMode.pixelHeight
                checks[prefix+"_own_window_not_pickable"] = !snapshot.targets.contains(where:{$0.id==UInt32(proof.windowNumber)})
                proof.orderOut(nil)
                guard cornerOK,checks[prefix+"_own_visible_window_excluded"]==true else { throw DisplayCapture.CaptureError.missing }
                let selector=SelectionView(image:image,frame:CGRect(origin:.zero,size:screen.frame.size))
                var selected: CGImage?
                selector.onConfirm={value,_,_ in selected=value}
                let region=CGRect(x:floor(screen.frame.width/2-520),y:floor(screen.frame.height/2-150),width:1040,height:300)
                func mouse(_ kind:NSEvent.EventType,_ point:CGPoint)->NSEvent {NSEvent.mouseEvent(with:kind,location:point,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
                selector.mouseDown(with:mouse(.leftMouseDown,region.origin));selector.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:region.maxX,y:region.maxY)));selector.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:region.maxX,y:region.maxY)));selector.confirm()
                guard let cropped=selected else {throw DisplayCapture.CaptureError.missing}
                checks[prefix+"_drag_crop_native_pixels"]=cropped.width==Int(region.width*sx) && cropped.height==Int(region.height*sy)
                selector.selectAll(nil);selector.confirm()
                checks[prefix+"_select_all_current_screen"]=selected?.width==image.width && selected?.height==image.height
                let ocrStarted=ProcessInfo.processInfo.systemUptime
                let editor=ImageWindow(image:cropped,pinned:false,preferences:AppPreferences(store:store))
                defer {editor.close()}
                await editor.recognitionForVerification?.value
                let ocrElapsed=(ProcessInfo.processInfo.systemUptime-ocrStarted)*1000
                let initialPNG=editor.stableImage().flatMap{ImageWindow.encoded($0,type:.png)}
                let text=editor.recognizedTextForVerification
                checks[prefix+"_captured_chinese_text_recognized"]=["今天下午三点半","图书馆门口见面","笔记本电脑","直接选择"].allSatisfy{text.contains($0)}
                editor.selectAll(nil);checks[prefix+"_select_all_exact_current_text"] = !text.isEmpty && editor.selectedTextForVerification==text
                var state=editor.annotationDocument.state
                state.objects=[AnnotationObject(tool:.arrow,style:.initial(.arrow),start:CGPoint(x:10,y:10),end:CGPoint(x:150,y:35))]
                editor.annotationDocument.commit(state)
                guard let composite=editor.stableImage(),let png=ImageWindow.encoded(composite,type:.png),let sourcePNG=ImageWindow.encoded(cropped,type:.png) else {throw DisplayCapture.CaptureError.missing}
                checks[prefix+"_annotation_changes_output"]=png != sourcePNG
                var pinCopy: AnnotationDocument?
                editor.onPin={pinCopy=$0};editor.pinImage()
                checks[prefix+"_pin_preserves_current_composite"]=pinCopy.flatMap{AnnotationRenderer.render(base:$0.baseImage,objects:$0.state.objects)}.flatMap{ImageWindow.encoded($0,type:.png)}==png
                editor.annotationDocument.undo();checks[prefix+"_undo_restores_empty_model"]=editor.annotationDocument.state.objects.isEmpty
                checks[prefix+"_undo_restores_initial_composite"]=editor.stableImage().flatMap{ImageWindow.encoded($0,type:.png)}==initialPNG
                if checks[prefix+"_captured_chinese_text_recognized"]==true {
                    let path=reportURL.deletingPathExtension().appendingPathExtension("screen-\(index).png");try png.write(to:path,options:.atomic)
                }
                rows.append(["index":index,"screen_scale":screen.backingScaleFactor,"display_pixels":[image.width,image.height],"framebuffer_pixels":[nativeMode.pixelWidth,nativeMode.pixelHeight],"filter_scale":nativeFilter.pointPixelScale,"filter_content_size":[nativeFilter.contentRect.width,nativeFilter.contentRect.height],"raw_png_equal_srgb_baseline":sourcePNG==initialPNG,"source_color_space":cropped.colorSpace?.name as String? ?? "unknown","composite_color_space":composite.colorSpace?.name as String? ?? "unknown","region_pixels":[cropped.width,cropped.height],"capture_attempts":attempts,"capture_with_enumeration_ms":elapsed,"safe_ocr_ms":ocrElapsed])
            } catch {checks[prefix+"_flow_completed"]=false;rows.append(["index":index,"status":"failed"])}
        }
        let passed = !checks.isEmpty && checks.values.allSatisfy{$0}
        write(["passed":passed,"fixture_only":true,"checks":checks,"screens":rows,"new_permissions":false,"scope":"真实ScreenCaptureKit整屏捕获独立样本进程，生产DisplayCapture函数与SelectionView/ImageWindow消费者；受控AppKit事件，不等同实体鼠标/键盘或首次安装。只保存已验证样本的区域合成，不保存整屏。"])
        return passed ? 0:1
    }
}
