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
        canvas.chooseTool(.rectangle)
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 80, y: 80)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 400, y: 220)))
        let blocksDraftExport = editor.stableImage() == nil
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 220)))
        let created = document.state.objects.first
        var result = layoutChecks
        result.merge(["draft_blocks_export": blocksDraftExport, "draw_event_creates_object": created?.tool == .rectangle && created?.bounds == CGRect(x: 80, y: 80, width: 320, height: 140)],uniquingKeysWith:{ _, new in new })
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
        result["move_event_updates_object"] = moved == CGRect(x: 120, y: 100, width: 320, height: 140)
        editor.undo(nil); result["move_undo"] = document.state.objects.first?.bounds == created?.bounds
        editor.redo(nil); result["move_redo"] = document.state.objects.first?.bounds == moved
        let corner = CGPoint(x: moved!.maxX, y: moved!.maxY)
        canvas.mouseDown(with: mouse(.leftMouseDown, corner))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: corner.x+80,y:corner.y+40)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: corner.x+80,y:corner.y+40)))
        result["resize_event_updates_object"] = document.state.objects.first?.bounds == CGRect(x: 120,y:100,width:400,height:180)
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
        descendants(editor.window!.contentView!).compactMap { $0 as? NSButton }.first(where: { $0.identifier?.rawValue == "style-width-16" })?.performClick(nil)
        result["style_buttons_route_to_current_tool"] = canvas.tool == .rectangle && preferences.annotationStyle(for: .rectangle).width == 16 && document.state.objects.first?.style.width == 12
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
        // 样式随选中工具自动出现；旧 --show-style 参数保留兼容，不再额外点击。
        await editor.recognitionForVerification?.value
        guard CGPreflightScreenCaptureAccess(), let window = editor.window else { return false }
        window.title = pinned ? "CcShot · 钉图样本" : "CcShot · 标注样本"
        window.contentView?.layoutSubtreeIfNeeded(); window.display(); CATransaction.flush()
        do {
            let snapshot = try await WindowCapture.capture(id: UInt32(window.windowNumber), ownerPID: ProcessInfo.processInfo.processIdentifier)
            guard let png = ImageWindow.encoded(snapshot, type: .png) else { return false }
            try png.write(to: URL(fileURLWithPath: path), options: .atomic); return true
        } catch { return false }
    }
}
