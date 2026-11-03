import AppKit
import QuartzCore

@MainActor enum TextVerification {
    static func run(reportPath: String, previewPath: String? = nil) async -> Bool {
        let suite = "com.ccshot.text-check.\(UUID().uuidString)"
        let store = UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        guard let context = CGContext(data:nil,width:1600,height:700,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x:0,y:0,width:1600,height:700))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:36,weight:.medium),.foregroundColor:NSColor.black]
        ("ORIGINAL PRIVATE 4832" as NSString).draw(at:CGPoint(x:40,y:500),withAttributes:attributes)
        ("PUBLIC BASE ABCD" as NSString).draw(at:CGPoint(x:40,y:60),withAttributes:attributes)
        NSGraphicsContext.restoreGraphicsState()
        guard let base = context.makeImage() else { return false }
        let editor = ImageWindow(image:base,pinned:false,preferences:AppPreferences(store:store))
        defer { editor.close() }
        let canvas = editor.canvas, document = editor.annotationDocument
        await editor.recognitionForVerification?.value
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        func mouse(_ point: CGPoint, count: Int = 1) -> NSEvent {
            let rect = canvas.contentRect
            let local = CGPoint(x:rect.minX+point.x/1600*rect.width,y:rect.minY+point.y/700*rect.height)
            return NSEvent.mouseEvent(with:.leftMouseDown,location:canvas.convert(local,to:nil),modifierFlags:[],timestamp:0,windowNumber:editor.window!.windowNumber,context:nil,eventNumber:1,clickCount:count,pressure:1)!
        }
        canvas.chooseTool(.text); canvas.mouseDown(with:mouse(CGPoint(x:100,y:400)))
        var checks = ["native_editor_opens":canvas.textEditor != nil,"pending_text_blocks_export":editor.stableImage() == nil]
        guard let input = canvas.textEditor else { return false }
        input.setMarkedText("zhongwen",selectedRange:NSRange(location:8,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        checks["composition_is_marked"] = input.hasMarkedText()
        checks["marked_candidate_blocks_commit"] = !canvas.finishTextEditing() && document.state.objects.isEmpty && editor.stableImage() == nil
        input.insertText("中文",replacementRange:input.markedRange())
        input.unmarkText()
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem(); for type in item.types { if let data = item.data(forType:type) { copy.setData(data,forType:type) } }; return copy
        } ?? []
        pasteboard.clearContents(); pasteboard.setString(" VBC 123\n第二行 😀",forType:.string)
        let written = pasteboard.changeCount
        let editMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where:{$0.title == "编辑"})
        checks["standard_paste_menu_exists"] = editMenu?.items.contains(where:{$0.action == #selector(NSText.paste(_:))}) == true
        checks["native_editor_has_focus"] = editor.window?.firstResponder === input && editor.window?.isKeyWindow == true
        if let index = editMenu?.items.firstIndex(where:{$0.action == #selector(NSText.paste(_:))}) { editMenu?.performActionForItem(at:index) }
        if pasteboard.changeCount == written { pasteboard.clearContents(); pasteboard.writeObjects(saved) }
        checks["standard_paste_menu_routes_to_editor"] = input.string == "中文 VBC 123\n第二行 😀"
        let expected = "中文 VBC 123\n第二行 😀"
        input.breakUndoCoalescing()
        if let index = editMenu?.items.firstIndex(where:{$0.action == #selector(ImageWindow.undo(_:))}) { editMenu?.performActionForItem(at:index) }
        checks["native_typing_undo_keeps_document_empty"] = input.string != expected && document.state.objects.isEmpty && !document.canUndo
        if let index = editMenu?.items.firstIndex(where:{$0.action == #selector(ImageWindow.redo(_:))}) { editMenu?.performActionForItem(at:index) }
        checks["native_typing_redo_restores_input"] = input.string == expected

        let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:editor.window!.windowNumber,context:nil,characters:"v",charactersIgnoringModifiers:"v",isARepeat:false,keyCode:9)!
        checks["tool_keys_do_not_handle_text_input"] = !canvas.handleKey(key) && canvas.tool == .text && input.string == expected
        checks["text_commits_exact_unicode"] = canvas.finishTextEditing() && document.state.objects.first?.text == expected && editor.stableImage() != nil
        await editor.recognitionForVerification?.value
        checks["rendered_text_is_recognizable"] = editor.recognizedTextForVerification.contains("VBC") && editor.recognizedTextForVerification.contains("第二行")
        if let previewPath {
            if CGPreflightScreenCaptureAccess(), let window = editor.window {
                window.title = "CcShot · 文字样本"; window.contentView?.layoutSubtreeIfNeeded(); window.display(); CATransaction.flush()
                do {
                    let image = try await WindowCapture.capture(id:UInt32(window.windowNumber),ownerPID:ProcessInfo.processInfo.processIdentifier)
                    guard let data = ImageWindow.encoded(image,type:.png) else { throw SafeTextImage.PreparationError.allocation }
                    try data.write(to:URL(fileURLWithPath:previewPath),options:.atomic); checks["native_preview"] = true
                } catch { checks["native_preview"] = false }
            } else { checks["native_preview"] = false }
        }
        document.undo(); checks["typing_is_one_document_undo"] = document.state.objects.isEmpty && !document.canUndo
        document.redo(); checks["redo_restores_text"] = document.state.objects.first?.text == expected
        let original = document.state.objects[0]
        let center = CGPoint(x:original.bounds.midX,y:original.bounds.midY)
        canvas.chooseTool(.select); canvas.mouseDown(with:mouse(center,count:2))
        canvas.textEditor?.insertText("取消的改动",replacementRange:NSRange(location:0,length:(expected as NSString).length))
        canvas.cancelTextEditing(); checks["cancel_preserves_existing_text"] = document.state.objects.first?.text == expected
        canvas.mouseDown(with:mouse(center,count:2)); canvas.textEditor?.string = "重新编辑"; _ = canvas.finishTextEditing()
        checks["double_click_edits_object"] = document.state.objects.first?.text == "重新编辑"
        document.undo(); checks["text_edit_undo"] = document.state.objects.first?.text == expected
        canvas.chooseTool(.text); canvas.mouseDown(with:mouse(CGPoint(x:1500,y:180))); canvas.textEditor?.string = String(repeating:"很长的文字",count:100)
        checks["overflow_stays_editable"] = !canvas.finishTextEditing() && canvas.textEditor != nil && document.state.objects.count == 1
        canvas.cancelTextEditing()
        document.commit(AnnotationState())
        canvas.chooseTool(.text); canvas.mouseDown(with:mouse(CGPoint(x:40,y:560)))
        var style = canvas.currentStyle; style.fontSize = 36; style.textBackground = true; style.color = .palette[6]
        canvas.changeStyle(style); canvas.textEditor?.string = "SAFE NOTE"; _ = canvas.finishTextEditing()
        await editor.recognitionForVerification?.value
        checks["background_keeps_user_text_hides_original"] = editor.recognizedTextForVerification.contains("SAFE NOTE") && !editor.recognizedTextForVerification.contains("PRIVATE") && !editor.recognizedTextForVerification.contains("4832") && editor.recognizedTextForVerification.contains("PUBLIC")
        let caption = document.state.objects[0]
        let mask = AnnotationObject(tool:.mask,style:.initial(.mask),start:CGPoint(x:caption.bounds.minX+20,y:caption.bounds.minY+10),end:CGPoint(x:caption.bounds.minX+50,y:caption.bounds.maxY-5))
        var state = document.state; state.objects = [caption,mask]; document.commit(state)
        await editor.recognitionForVerification?.value
        checks["later_mask_suppresses_annotation_text"] = !editor.recognizedTextForVerification.contains("SAFE") && editor.recognizedTextForVerification.contains("PUBLIC")
        state.objects = [mask,caption]; document.commit(state)
        await editor.recognitionForVerification?.value
        checks["text_above_mask_remains_visible"] = editor.recognizedTextForVerification.contains("SAFE NOTE") && !editor.recognizedTextForVerification.contains("PRIVATE")
        let passed = checks.values.allSatisfy { $0 }
        let result: [String:Any] = ["fixture_only":true,"checks":checks,"passed":passed,"physical_ime_tested":false,"composition_scope":"直接调用原生NSTextInputClient标记/插入；不冒充真实中文输入法候选实测"]
        if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic) }
        return passed
    }
}
