import AppKit
import QuartzCore

@MainActor enum PrivacyVerification {
    static func run(reportPath: String, previewPath: String? = nil, checkClipboard: Bool = true) async -> Bool {
        let suite = "com.ccshot.privacy-check.\(UUID().uuidString)"
        let store = UserDefaults(suiteName:suite)!
        defer { store.removePersistentDomain(forName:suite) }
        guard let context = CGContext(data: nil, width: 1000, height: 320, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x:0,y:0,width:1000,height:320))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context, flipped:false)
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:36,weight:.medium),.foregroundColor:NSColor.black]
        ("PRIVATE CODE 4832" as NSString).draw(at:CGPoint(x:50,y:200),withAttributes:attributes)
        ("PUBLIC NOTE ABCD" as NSString).draw(at:CGPoint(x:50,y:80),withAttributes:attributes)
        NSGraphicsContext.restoreGraphicsState()
        guard let base = context.makeImage() else { return false }
        let editor = ImageWindow(image:base,pinned:false,preferences:AppPreferences(store:store))
        defer { editor.close() }
        let document = editor.annotationDocument
        await editor.recognitionForVerification?.value
        var result: [String:Bool] = ["baseline_recognizes_both_lines":editor.recognizedTextForVerification.contains("PRIVATE") && editor.recognizedTextForVerification.contains("PUBLIC")]
        let baselinePNG = editor.stableImage().flatMap { ImageWindow.encoded($0,type:.png) }
        var latestMask: AnnotationObject!
        for effect in MaskEffect.allCases {
            for brush in [false,true] {
                var style = AnnotationStyle.initial(.mask); style.maskEffect = effect; style.maskBrush = brush; style.width = 20; style.maskStrength = 20
                let mask = AnnotationObject(tool:.mask,style:style,start:CGPoint(x:220,y:206),end:CGPoint(x:245,y:225),points:brush ? [CGPoint(x:220,y:206),CGPoint(x:245,y:225)] : [])
                latestMask = mask
                var state = document.state; state.objects = [mask]
                editor.selectAll(nil); document.commit(state)
                let name = "\(effect.rawValue)_\(brush ? "brush" : "rectangle")"
                result[name+"_old_text_cleared_immediately"] = editor.recognizedTextForVerification.isEmpty && editor.selectedTextForVerification.isEmpty
                result[name+"_composite_changed"] = editor.stableImage().flatMap { ImageWindow.encoded($0,type:.png) }.map { $0 != baselinePNG } ?? false
                await editor.recognitionForVerification?.value
                let text = editor.recognizedTextForVerification
                result[name+"_suppresses_entire_private_unit"] = !text.contains("PRIVATE") && !text.contains("4832") && text.contains("PUBLIC")
                editor.selectAll(nil)
                result[name+"_selection_matches_safe_text"] = !text.isEmpty && editor.selectedTextForVerification == text
                if checkClipboard {
                    let pasteboard = NSPasteboard.general
                    let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
                        let copy = NSPasteboardItem()
                        for type in item.types { if let data = item.data(forType:type) { copy.setData(data,forType:type) } }
                        return copy
                    } ?? []
                    editor.copyAllText(); let written = pasteboard.changeCount
                    let copied = pasteboard.string(forType:.string) ?? ""
                    result[name+"_copy_all_uses_safe_text"] = !copied.contains("PRIVATE") && !copied.contains("4832") && copied.contains("PUBLIC")
                    if pasteboard.changeCount == written { pasteboard.clearContents(); pasteboard.writeObjects(saved) }
                }
            }
        }
        var moved = document.state; moved.objects = [latestMask.moved(by:CGPoint(x:500,y:-160))]; document.commit(moved)
        await editor.recognitionForVerification?.value
        result["moving_mask_restores_visible_text"] = editor.recognizedTextForVerification.contains("PRIVATE") && editor.recognizedTextForVerification.contains("4832")
        document.undo(); result["undo_clears_old_text"] = editor.recognizedTextForVerification.isEmpty
        await editor.recognitionForVerification?.value
        result["undo_restores_suppression"] = !editor.recognizedTextForVerification.contains("PRIVATE") && editor.recognizedTextForVerification.contains("PUBLIC")
        document.redo(); await editor.recognitionForVerification?.value
        result["redo_restores_visible_text"] = editor.recognizedTextForVerification.contains("PRIVATE")
        // 普通实心图形也按遮挡处理。
        var filled = AnnotationStyle.initial(.rectangle); filled.filled = true
        var fillState = document.state; fillState.objects = [AnnotationObject(tool:.rectangle,style:filled,start:CGPoint(x:220,y:206),end:CGPoint(x:245,y:225))]; document.commit(fillState)
        await editor.recognitionForVerification?.value
        result["filled_shape_also_suppresses_private_unit"] = !editor.recognizedTextForVerification.contains("PRIVATE") && editor.recognizedTextForVerification.contains("PUBLIC")
        if let previewPath {
            var previewStyle = AnnotationStyle.initial(.mask); previewStyle.maskStrength = 20
            var previewState = document.state
            previewState.objects = [AnnotationObject(tool:.mask,style:previewStyle,start:CGPoint(x:200,y:195),end:CGPoint(x:285,y:246))]
            document.commit(previewState); editor.canvas.chooseTool(.mask)
            await editor.recognitionForVerification?.value
            if CGPreflightScreenCaptureAccess(), let window = editor.window {
                window.title = "CcShot · 遮挡样本"; window.contentView?.layoutSubtreeIfNeeded(); window.display(); CATransaction.flush()
                do {
                    let image = try await WindowCapture.capture(id:UInt32(window.windowNumber),ownerPID:ProcessInfo.processInfo.processIdentifier)
                    guard let data = ImageWindow.encoded(image,type:.png) else { throw SafeTextImage.PreparationError.allocation }
                    try data.write(to:URL(fileURLWithPath:previewPath),options:.atomic); result["native_preview"] = true
                } catch { result["native_preview"] = false }
            } else { result["native_preview"] = false }
        }
        document.commit(moved)
        let late = editor.recognitionForVerification
        editor.close(); await late?.value
        result["closed_window_has_no_old_analysis"] = editor.recognizedTextForVerification.isEmpty
        let passed = result.values.allSatisfy { $0 }
        let report: [String:Any] = ["fixture_only":true,"clipboard_tested":checkClipboard,"test_data":"两行虚构英文，仅局部遮挡第一行；不记录私人截图或OCR","checks":result,"passed":passed]
        if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:reportPath),options:.atomic) }
        return passed
    }
}
