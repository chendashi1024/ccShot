import AppKit
import QuartzCore

extension ImageWindow {
    static func annotationChecks(_ image: CGImage) -> [String: Bool] {
        let suite = "com.ccshot.annotation-consumer.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(store: store)
        let editor = ImageWindow(image: image, pinned: false, preferences: preferences)
        defer { editor.close() }
        let layoutChecks = editor.coreLayoutChecks()
        let canvas = editor.canvas, document = editor.annotationDocument
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            let rect = canvas.contentRect
            let local = CGPoint(x: rect.minX+point.x/CGFloat(image.width)*rect.width, y: rect.minY+point.y/CGFloat(image.height)*rect.height)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: editor.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        // 视图坐标与图片像素来回换算会产生浮点尾差，误差仍须小于百万分之一像素。
        func near(_ actual: CGPoint?, _ expected: CGPoint) -> Bool {
            guard let actual else { return false }
            return abs(actual.x-expected.x) < 0.000001 && abs(actual.y-expected.y) < 0.000001
        }
        func near(_ actual: CGRect?, _ expected: CGRect) -> Bool {
            guard let actual else { return false }
            return near(actual.origin, expected.origin)
                && abs(actual.width-expected.width) < 0.000001 && abs(actual.height-expected.height) < 0.000001
        }
        canvas.chooseTool(.rectangle)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 80, y: 80)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 400, y: 220)))
        let blocksDraftExport = editor.stableImage() == nil
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 220)))
        let created = document.state.objects.first
        var result = layoutChecks
        result.merge(["draft_blocks_export": blocksDraftExport, "draw_event_creates_object": created?.tool == .rectangle && near(created?.bounds, CGRect(x: 80, y: 80, width: 320, height: 140))],uniquingKeysWith:{ _, new in new })
        let untouchedDefault = preferences.annotationStyle(for: .rectangle)
        var style = canvas.currentStyle; style.width = 12; style.filled = true
        canvas.changeStyle(style)
        result["selected_style_keeps_tool_default"] = preferences.annotationStyle(for: .rectangle) == untouchedDefault && document.state.objects.first?.style.width == 12
        let markedImage = editor.stableImage()
        result["composite_contains_annotation"] = markedImage.flatMap { PixelSampler.color(in: $0, x: 150, y: image.height-1-150) }.map { $0.red > 230 && $0.green < 100 } ?? false
        canvas.chooseTool(.select)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 200, y: 150)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 240, y: 170)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 240, y: 170)))
        let moved = document.state.objects.first?.bounds
        result["move_event_updates_object"] = near(moved, CGRect(x: 120, y: 100, width: 320, height: 140))
        editor.undo(nil); result["move_undo"] = document.state.objects.first?.bounds == created?.bounds
        editor.redo(nil); result["move_redo"] = document.state.objects.first?.bounds == moved
        let corner = CGPoint(x: moved!.maxX, y: moved!.maxY)
        canvas.mouseDown(with: mouse(.leftMouseDown, corner))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: corner.x+80,y:corner.y+40)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: corner.x+80,y:corner.y+40)))
        result["resize_event_updates_object"] = near(document.state.objects.first?.bounds, CGRect(x: 120,y:100,width:400,height:180))
        let count = document.state.objects.count
        canvas.chooseTool(.pen); canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 10,y:20))); canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 50,y:60))); canvas.cancelGesture()
        result["cancel_gesture_keeps_document"] = document.state.objects.count == count && editor.stableImage() != nil
        canvas.chooseTool(.number)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 700,y:200)))
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 800,y:200)))
        result["number_sequence"] = document.state.objects.suffix(2).map(\.number) == [1,2] && document.state.nextNumber == 3
        editor.undo(nil); result["number_undo_restores_next"] = document.state.nextNumber == 2
        editor.redo(nil)
        var pinCopy: AnnotationDocument?
        editor.onPin = { pinCopy = $0 }; editor.pinImage()
        result["pin_keeps_editable_objects"] = pinCopy?.state == document.state && pinCopy !== document
        if let pinCopy {
            let pin = ImageWindow(annotationDocument: pinCopy, pinned: true, preferences: preferences)
            let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: pin.window!.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
            pin.window!.sendEvent(space)
            result["pin_initial_space_enters_editing"] = pin.canvas.editingEnabled
            pinCopy.undo()
            result["pin_edit_independent"] = pinCopy.state != document.state && document.state.nextNumber == 3 && pin.stableImage() != nil
            let expectedPNG = pin.stableImage().flatMap { Self.encoded($0, type: .png) }
            if let opacity = pin.canvas.menu?.items.first(where:{$0.title == "透明度"})?.submenu, let index = opacity.items.firstIndex(where:{$0.tag == 50}) { opacity.performActionForItem(at:index) }
            result["pin_opacity_menu_changes_view_only"] = pin.window?.alphaValue == 0.5
            if let menu = pin.canvas.menu, let index = menu.items.firstIndex(where:{$0.action == #selector(ImageWindow.copyImage)}) { menu.performActionForItem(at:index) }
            result["context_copy_uses_composite"] = expectedPNG != nil && NSPasteboard.general.data(forType:.png) == expectedPNG
            pin.copyImage()
            result["pin_copy_uses_composite"] = expectedPNG != nil && NSPasteboard.general.data(forType: .png) == expectedPNG && pin.window?.isVisible == true
            pin.close()
        }
        document.beginTransaction(); result["transaction_blocks_export"] = editor.stableImage() == nil; document.endTransaction()
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(editor.window!.contentView!).compactMap { $0 as? NSButton }
        buttons.first(where: { $0.title == "画框" })?.performClick(nil)
        editor.window!.contentView!.layoutSubtreeIfNeeded()
        let preset = descendants(editor.window!.contentView!).compactMap { $0 as? NSButton }.last {
            !$0.isHidden && $0.identifier?.rawValue.hasPrefix("style-width-") == true
        }
        preset?.performClick(nil)
        result["style_buttons_route_to_current_tool"] = canvas.tool == .rectangle && preset.map { preferences.annotationStyle(for: .rectangle).width == CGFloat($0.tag) } == true && document.state.objects.first?.style.width == 12
        canvas.chooseTool(.arrow)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100,y:100)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 250,y:150)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 250,y:150)))
        let arrowCount = document.state.objects.count
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 250,y:150)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300,y:180)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300,y:180)))
        result["visible_endpoint_edits_in_arrow_mode"] = document.state.objects.count == arrowCount && near(document.state.objects.last?.end, CGPoint(x:300,y:180)) && canvas.tool == .arrow
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 150,y:120)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 190,y:140)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 190,y:140)))
        result["selected_arrow_body_moves_without_new_object"] = document.state.objects.count == arrowCount && near(document.state.objects.last?.start, CGPoint(x:140,y:120)) && near(document.state.objects.last?.end, CGPoint(x:340,y:200))
        editor.undo(nil)
        result["direct_arrow_move_undo"] = near(document.state.objects.last?.start, CGPoint(x:100,y:100)) && near(document.state.objects.last?.end, CGPoint(x:300,y:180))
        let straight = document.state.objects.last!
        result["arrow_defaults_to_straight"] = straight.curveControl == nil
        func dragArrow(_ from: CGPoint,_ to: CGPoint) {
            canvas.mouseDown(with:mouse(.leftMouseDown,from)); canvas.mouseDragged(with:mouse(.leftMouseDragged,to)); canvas.mouseUp(with:mouse(.leftMouseUp,to))
        }
        dragArrow(straight.arrowMidpoint,CGPoint(x:200,y:240))
        let curved = document.state.objects.last!
        result["middle_handle_bends_existing_arrow"] = document.state.objects.count == arrowCount && curved.start == straight.start && curved.end == straight.end && hypot(curved.arrowMidpoint.x-200,curved.arrowMidpoint.y-240) < 0.01
        result["curved_hit_follows_visible_line"] = curved.hit(curved.arrowPoint(at:0.25),tolerance:1) && !curved.hit(straight.arrowMidpoint,tolerance:1)
        editor.undo(nil); result["bend_undo_restores_straight"] = document.state.objects.last == straight
        editor.redo(nil); result["bend_redo_restores_curve"] = document.state.objects.last == curved
        canvas.mouseDown(with:mouse(.leftMouseDown,curved.arrowMidpoint)); canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:200,y:280))); canvas.cancelGesture()
        result["bend_cancel_preserves_curve"] = document.state.objects.last == curved && !canvas.hasDraft
        let body = curved.arrowPoint(at:0.25)
        dragArrow(body,CGPoint(x:body.x+30,y:body.y+10))
        result["curved_body_moves_all_geometry"] = document.state.objects.last?.id == curved.id && near(document.state.objects.last?.start, CGPoint(x:130,y:110)) && near(document.state.objects.last?.end, CGPoint(x:330,y:190)) && near(document.state.objects.last?.curveControl, CGPoint(x:230,y:350))
        editor.undo(nil)
        dragArrow(curved.end,CGPoint(x:350,y:200))
        result["curved_endpoint_retains_bend"] = near(document.state.objects.last?.end, CGPoint(x:350,y:200)) && near(document.state.objects.last?.curveControl, CGPoint(x:225,y:350))
        editor.undo(nil)
        let copy = document.copied(); copy.undo()
        result["curved_pin_copy_is_independent"] = document.state.objects.last == curved && copy.state.objects.last == straight
        dragArrow(curved.arrowMidpoint,straight.arrowMidpoint)
        result["middle_handle_can_restore_straight"] = near(document.state.objects.last?.arrowMidpoint, straight.arrowMidpoint) && near(document.state.objects.last?.strokePath.boundingBoxOfPath, straight.strokePath.boundingBoxOfPath)
        editor.undo(nil)
        dragArrow(curved.arrowMidpoint,CGPoint(x:200,y:CGFloat(image.height)))
        let box = document.state.objects.last!.strokePath.boundingBoxOfPath
        result["bending_stays_inside_image"] = box.maxY <= CGFloat(image.height) && box.minY >= 0 && box.minX >= 0 && box.maxX <= CGFloat(image.width)
        editor.undo(nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20,y:300)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 70,y:340)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 70,y:340)))
        result["empty_canvas_still_draws_arrow"] = document.state.objects.count == arrowCount+1
        return result
    }
    static func annotationPreview(_ image: CGImage, to path: String) async -> Bool {
        let pinned = CommandLine.arguments.contains("--preview-pin")
        let suite = "com.ccshot.annotation-preview.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        // 预览不写用户偏好，也不读取用户截图。
        defer { store.removePersistentDomain(forName: suite) }
        let size = CGSize(width: 1000,height:480)
        guard let context = CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(origin:.zero,size:size))
        context.draw(image,in:CGRect(x:30,y:230,width:940,height:225))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        ("本地选字 · 标注对象可以继续修改" as NSString).draw(at:CGPoint(x:44,y:160),withAttributes:[.font:NSFont.systemFont(ofSize:25),.foregroundColor:NSColor.black])
        ("拖动控制点调整形状，复制与钉图使用同一份合成结果。" as NSString).draw(at:CGPoint(x:44,y:110),withAttributes:[.font:NSFont.systemFont(ofSize:20),.foregroundColor:NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState()
        guard let base = context.makeImage() else { return false }
        let document = AnnotationDocument(image:base)
        var state = document.state
        var blue = AnnotationStyle.initial(.rectangle); blue.color = .palette[4]; blue.cornerRadius = 12
        state.objects.append(AnnotationObject(tool:.rectangle,style:blue,start:CGPoint(x:30,y:280),end:CGPoint(x:960,y:440)))
        state.objects.append(AnnotationObject(tool:.arrow,style:.initial(.arrow),start:CGPoint(x:820,y:180),end:CGPoint(x:640,y:260)))
        state.objects.append(AnnotationObject(tool:.highlight,style:.initial(.highlight),start:CGPoint(x:50,y:164),end:CGPoint(x:470,y:164),points:[CGPoint(x:50,y:164),CGPoint(x:470,y:164)]))
        state.objects.append(AnnotationObject(tool:.number,style:.initial(.number),start:CGPoint(x:880,y:90),end:CGPoint(x:928,y:138)))
        document.commit(state)
        let editor = ImageWindow(annotationDocument:document,pinned:pinned,preferences:AppPreferences(store:store))
        defer { editor.close() }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        if pinned && CommandLine.arguments.contains("--preview-edit") { if let root = editor.window?.contentView { descendants(root).compactMap { $0 as? NSButton }.first(where:{$0.title == "标注"})?.performClick(nil) } }
        if !pinned || CommandLine.arguments.contains("--preview-edit") { editor.canvas.chooseTool(CommandLine.arguments.contains("--preview-text") ? .text : .arrow) }
        if CommandLine.arguments.contains("--preview-curved-arrow") {
            let canvas = editor.canvas
            canvas.chooseTool(.select); editor.window?.contentView?.layoutSubtreeIfNeeded()
            func mouse(_ type: NSEvent.EventType,_ point: CGPoint) -> NSEvent {
                let rect = canvas.contentRect
                let local = CGPoint(x:rect.minX+point.x/size.width*rect.width,y:rect.minY+point.y/size.height*rect.height)
                return NSEvent.mouseEvent(with:type,location:canvas.convert(local,to:nil),modifierFlags:[],timestamp:0,windowNumber:editor.window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            }
            let middle = CGPoint(x:730,y:220), bent = CGPoint(x:800,y:290)
            canvas.mouseDown(with:mouse(.leftMouseDown,middle)); canvas.mouseUp(with:mouse(.leftMouseUp,middle))
            canvas.mouseDown(with:mouse(.leftMouseDown,middle)); canvas.mouseDragged(with:mouse(.leftMouseDragged,bent)); canvas.mouseUp(with:mouse(.leftMouseUp,bent))
        }
        // 样式随选中工具自动出现；旧 --show-style 参数保留兼容，不再额外点击。
        await editor.recognitionForVerification?.value
        guard CGPreflightScreenCaptureAccess(), let window = editor.window else { return false }
        window.title = pinned ? "ccShot · 钉图样本" : "ccShot · 标注样本"
        window.contentView?.layoutSubtreeIfNeeded(); window.display(); CATransaction.flush()
        do {
            let snapshot = try await WindowCapture.capture(id: UInt32(window.windowNumber), ownerPID: ProcessInfo.processInfo.processIdentifier)
            guard let png = ImageWindow.encoded(snapshot, type: .png) else { return false }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic); return true
        } catch { return false }
    }
}
