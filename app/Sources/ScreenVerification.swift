import AppKit
import ScreenCaptureKit
import QuartzCore

@MainActor enum ScreenVerification {
    static func run(_ image: CGImage, reportPath: String) async -> Int32 {
        func write(_ value: [String:Any]) {
            if let data = try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic) }
        }
        guard CGPreflightScreenCaptureAccess() else { write(["status":"skipped","reason":"existing_permission_missing","passed":false]); return 2 }
        guard image.width >= 1800, image.height >= 260 else { write(["status":"skipped","reason":"fixture_size_unsupported","passed":false]); return 2 }
        let screens = NSScreen.screens
        guard let primary = screens.first else { write(["status":"skipped","reason":"no_screen","passed":false]); return 2 }
        let suite = "com.ccshot.screen-check.\(UUID().uuidString)"
        let store = UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        let document = AnnotationDocument(image:image)
        var state = document.state, style = AnnotationStyle.initial(.rectangle)
        style.filled = true
        let marker = AnnotationObject(tool:.rectangle,style:style,start:CGPoint(x:80,y:80),end:CGPoint(x:400,y:240))
        state.objects = [marker]; document.commit(state)
        let pin = ImageWindow(annotationDocument:document,pinned:true,preferences:AppPreferences(store:store))
        defer { pin.close() }
        await pin.recognitionForVerification?.value
        guard let window = pin.window, let baseline = pin.stableImage().flatMap({ImageWindow.encoded($0,type:.png)}) else { return 1 }
        let space = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
        window.sendEvent(space)
        var checks: [String:Bool] = ["pin_can_edit":pin.canvas.editingEnabled]
        var rows: [[String:Any]] = []
        for (index, screen) in screens.enumerated() {
            let prefix = "screen_\(index)"
            document.commit(state); pin.canvas.chooseTool(.select)
            let visible = screen.visibleFrame
            let frame = CGRect(x:floor(visible.midX-460),y:floor(visible.maxY-480),width:920,height:440)
            window.setFrame(frame,display:true); window.contentView?.layoutSubtreeIfNeeded()
            await pin.recognitionForVerification?.value
            window.title = "ccShot · 双屏样本 \(index+1)"; window.display(); CATransaction.flush()
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard let target = content.windows.first(where:{$0.windowID == UInt32(window.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier}) else { throw WindowCapture.CaptureError.missing }
                let local = WindowTarget.localRect(quartzFrame:target.frame,screenFrame:screen.frame,primaryTop:primary.frame.maxY)
                let expected = window.frame.offsetBy(dx:-screen.frame.minX,dy:-screen.frame.minY)
                checks[prefix+"_quartz_to_local"] = local.map { abs($0.minX-expected.minX) < 0.01 && abs($0.minY-expected.minY) < 0.01 && abs($0.width-expected.width) < 0.01 && abs($0.height-expected.height) < 0.01 } ?? false
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                checks[prefix+"_window_on_requested_screen"] = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == displayID
                checks[prefix+"_self_excluded_from_window_targets"] = !WindowCapture.targets(in:content,screen:screen).contains(where:{$0.id == UInt32(window.windowNumber)})
                let captured: CGImage
                do {
                    // 系统会将子工具栏与钉图合并后缩放，像素对齐检查只取钉图本体。
                    let toolbars = (window.childWindows ?? []).map { (window: $0, wasVisible: $0.isVisible) }
                    for toolbar in toolbars {
                        window.removeChildWindow(toolbar.window)
                        toolbar.window.orderOut(nil)
                    }
                    defer {
                        for toolbar in toolbars {
                            window.addChildWindow(toolbar.window, ordered: .above)
                            if !toolbar.wasVisible { toolbar.window.orderOut(nil) }
                        }
                    }
                    CATransaction.flush()
                    captured = try await WindowCapture.capture(id:UInt32(window.windowNumber),ownerPID:ProcessInfo.processInfo.processIdentifier)
                }
                let filter = SCContentFilter(desktopIndependentWindow:target)
                let scale = CGFloat(filter.pointPixelScale)
                checks[prefix+"_capture_native_size"] = captured.width == Int(ceil(window.frame.width*scale)) && captured.height == Int(ceil(window.frame.height*scale))
                func sample(_ point: CGPoint) -> SampledColor? {
                    let rect = pin.canvas.contentRect
                    let view = CGPoint(x:rect.minX+point.x/CGFloat(image.width)*rect.width,y:rect.minY+point.y/CGFloat(image.height)*rect.height)
                    let inWindow = pin.canvas.convert(view,to:nil)
                    return PixelSampler.color(in:captured,x:Int((inWindow.x*scale).rounded()),y:captured.height-1-Int((inWindow.y*scale).rounded()))
                }
                let red = sample(CGPoint(x:200,y:180)), white = sample(CGPoint(x:1700,y:180))
                checks[prefix+"_rendered_marker_and_base_align"] = (red.map{$0.red > 200 && $0.green < 130} ?? false) && (white.map{$0.red > 245 && $0.green > 245 && $0.blue > 245} ?? false)
                checks[prefix+"_export_keeps_source_pixels"] = pin.stableImage().flatMap { ImageWindow.encoded($0,type:.png) } == baseline
                let text = pin.recognizedTextForVerification
                pin.selectAll(nil)
                checks[prefix+"_select_all_matches_safe_text"] = !text.isEmpty && pin.selectedTextForVerification == text
                pin.canvas.chooseTool(.select)
                func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                    let rect = pin.canvas.contentRect
                    let local = CGPoint(x:rect.minX+point.x/CGFloat(image.width)*rect.width,y:rect.minY+point.y/CGFloat(image.height)*rect.height)
                    return NSEvent.mouseEvent(with:type,location:pin.canvas.convert(local,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
                }
                pin.canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:200,y:180)))
                pin.canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:210,y:185)))
                pin.canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:210,y:185)))
                let moved = document.state.objects[0].bounds
                checks[prefix+"_edit_event_tracks_source_coordinates"] = abs(moved.minX-90) < 0.000001 && abs(moved.minY-85) < 0.000001
                document.undo(); checks[prefix+"_undo_restores_exact_export"] = pin.stableImage().flatMap { ImageWindow.encoded($0,type:.png) } == baseline
                var row: [String:Any] = ["index":index,"logical_frame":[screen.frame.minX,screen.frame.minY,screen.frame.width,screen.frame.height],"screen_scale":screen.backingScaleFactor,"window_scale":window.backingScaleFactor,"capture_scale":scale,"quartz_window_frame":[target.frame.minX,target.frame.minY,target.frame.width,target.frame.height],"capture_pixels":[captured.width,captured.height]]
                if checks[prefix+"_rendered_marker_and_base_align"] == true, let data = ImageWindow.encoded(captured,type:.png) {
                    let path = URL(fileURLWithPath:reportPath).deletingPathExtension().appendingPathExtension("screen-\(index).png")
                    try data.write(to:path,options:.atomic); row["own_window_capture_file"] = path.lastPathComponent
                }
                rows.append(row)
            } catch { checks[prefix+"_capture_and_mapping"] = false; rows.append(["index":index,"status":"failed"]) }
        }
        let passed = checks.values.allSatisfy{$0}
        write(["fixture_only":true,"screens":rows,"checks":checks,"passed":passed,"scope":"真实当前显示器上移动本进程样本窗口并捕获；受控AppKit事件编辑，不等同实体鼠标/全局键测试","mixed_1x_2x_available":Set(screens.map(\.backingScaleFactor)).count > 1,"source_pixels":[image.width,image.height]])
        return passed ? 0 : 1
    }
}
