import AppKit

// 直接经过原生窗口和画布事件入口，防止只测文档历史而漏掉快捷键、焦点和命中问题。
@MainActor final class InteractionFixture {
    let suite = "com.ccshot.interaction-tests.\(UUID().uuidString)"
    let store: UserDefaults
    let editor: ImageWindow
    let pasteboard = NSPasteboard.withUniqueName()
    var canvas: AnnotationCanvas { editor.canvas }
    var document: AnnotationDocument { editor.annotationDocument }
    var window: AnnotationWindow { editor.window as! AnnotationWindow }
    init(pinned: Bool = false, withText: Bool = false) {
        store = UserDefaults(suiteName: suite)!
        let context = CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        if withText {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            ("Select this text" as NSString).draw(at: CGPoint(x: 120, y: 180),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = context.makeImage()!
        let presentation = ScreenshotPresentation(background: image, screenFrame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                                                  region: CGRect(x: 150, y: 250, width: 800, height: 500), displayID: 0, allowsAdjustment: false)
        editor = ImageWindow(annotationDocument: AnnotationDocument(image: image), pinned: pinned,
                             preferences: AppPreferences(store: store), screenshot: presentation, pasteboard: pasteboard)
        window.contentView?.layoutSubtreeIfNeeded()
    }
    func close() { editor.close(); store.removePersistentDomain(forName: suite); pasteboard.releaseGlobally() }
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint, flags: NSEvent.ModifierFlags = [], count: Int = 1) {
        let r = canvas.contentRect
        let local = CGPoint(x: r.minX + p.x / 800 * r.width, y: r.minY + p.y / 500 * r.height)
        let event = NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: flags,
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        window.sendEvent(event)
    }
    func drag(_ a: CGPoint, _ b: CGPoint, flags: NSEvent.ModifierFlags = []) {
        mouse(.leftMouseDown, a, flags: flags); mouse(.leftMouseDragged, b, flags: flags); mouse(.leftMouseUp, b, flags: flags)
    }
    func key(_ code: UInt16, _ text: String = "", flags: NSEvent.ModifierFlags = [], direct: Bool = false) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        if direct || !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }
    func rectangle() { canvas.chooseTool(.rectangle); drag(CGPoint(x: 100, y: 100), CGPoint(x: 350, y: 250)) }
}

@main struct InteractionTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ body: (InteractionFixture) -> Bool) {
            let f = InteractionFixture(); defer { f.close() }
            checks[name] = body(f)
        }
        check("空心框内部拖动不新增对象") { f in
            f.rectangle(); let id = f.document.state.objects.first?.id
            f.drag(CGPoint(x: 200, y: 170), CGPoint(x: 230, y: 190))
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.id == id
                && f.document.state.objects.first?.bounds == CGRect(x: 130, y: 120, width: 250, height: 150)
        }
        check("取消选择后仍可拖动旧框") { f in
            f.rectangle(); f.canvas.chooseTool(.rectangle)
            f.drag(CGPoint(x: 200, y: 170), CGPoint(x: 220, y: 180))
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.start == CGPoint(x: 120, y: 110)
        }
        check("Option可在旧框内部另画框") { f in
            f.rectangle(); f.drag(CGPoint(x: 180, y: 150), CGPoint(x: 260, y: 210), flags: .option)
            return f.document.state.objects.count == 2 && f.document.state.objects.last?.bounds == CGRect(x: 180, y: 150, width: 80, height: 60)
        }
        check("空白处继续绘制") { f in
            f.rectangle(); f.drag(CGPoint(x: 500, y: 100), CGPoint(x: 650, y: 200))
            return f.document.state.objects.count == 2
        }
        check("框内切换箭头工具仍可绘制箭头") { f in
            f.rectangle(); f.canvas.chooseTool(.arrow)
            f.drag(CGPoint(x: 160, y: 140), CGPoint(x: 270, y: 200))
            return f.document.state.objects.map(\.tool) == [.rectangle, .arrow]
                && f.document.state.objects.first?.start == CGPoint(x: 100, y: 100)
        }
        for flags: NSEvent.ModifierFlags in [.command, .control] {
            check("\(flags == .command ? "Command" : "Control")撤销重做经过窗口入口") { f in
                f.rectangle(); let before = f.document.state
                f.key(6, "z", flags: flags)
                let undone = f.document.state.objects.isEmpty
                f.key(6, "z", flags: [flags, .shift])
                return undone && f.document.state == before
            }
        }
        check("ControlY重做") { f in
            f.rectangle(); f.editor.undo(nil); f.key(16, "y", flags: .control)
            return f.document.state.objects.count == 1
        }
        check("ControlZ普通按键分发也能撤销") { f in
            f.rectangle(); f.key(6, "z", flags: .control, direct: true)
            return f.document.state.objects.isEmpty
        }
        check("工具栏获取焦点后仍可撤销") { f in
            f.rectangle()
            @MainActor func children(_ v: NSView) -> [NSView] { v.subviews.flatMap { [$0] + children($0) } }
            if let button = children(f.window.contentView!).compactMap({ $0 as? NSButton }).first(where: { !$0.isHidden }) {
                f.window.makeFirstResponder(button)
            }
            f.key(6, "z", flags: .command)
            return f.document.state.objects.isEmpty
        }
        check("一次拖动只需撤销一次") { f in
            f.rectangle(); let before = f.document.state
            f.drag(CGPoint(x: 200, y: 170), CGPoint(x: 230, y: 190)); f.editor.undo(nil)
            return f.document.state == before
        }
        check("单击选中不污染历史") { f in
            f.rectangle(); f.canvas.chooseTool(.select)
            f.drag(CGPoint(x: 100, y: 170), CGPoint(x: 100, y: 170)); f.editor.undo(nil)
            return f.document.state.objects.isEmpty
        }
        check("Delete删除与撤销恢复") { f in
            f.rectangle(); let before = f.document.state; f.key(51)
            let deleted = f.document.state.objects.isEmpty; f.editor.undo(nil)
            return deleted && f.document.state == before
        }
        check("撤销后新编辑清空重做") { f in
            f.rectangle(); f.editor.undo(nil); f.canvas.chooseTool(.arrow)
            f.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
            return f.document.state.objects.count == 1 && !f.document.canRedo
        }
        check("Esc取消正在拖动且保留原图形") { f in
            f.rectangle(); let before = f.document.state
            f.mouse(.leftMouseDown, CGPoint(x: 200, y: 170)); f.mouse(.leftMouseDragged, CGPoint(x: 250, y: 180))
            f.key(53); f.mouse(.leftMouseUp, CGPoint(x: 250, y: 180))
            return f.document.state == before && !f.canvas.hasDraft && f.window.isVisible
        }
        check("拖动中撤销先取消本次操作") { f in
            f.rectangle(); let before = f.document.state
            f.mouse(.leftMouseDown, CGPoint(x: 200, y: 170)); f.mouse(.leftMouseDragged, CGPoint(x: 250, y: 180))
            f.key(6, "z", flags: .control); f.mouse(.leftMouseUp, CGPoint(x: 250, y: 180))
            return f.document.state == before && !f.canvas.hasDraft
        }
        check("拖动中Delete不会复活或复制对象") { f in
            f.rectangle()
            f.mouse(.leftMouseDown, CGPoint(x: 200, y: 170)); f.mouse(.leftMouseDragged, CGPoint(x: 230, y: 190))
            f.key(51); f.mouse(.leftMouseUp, CGPoint(x: 230, y: 190)); f.editor.undo(nil)
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.start == CGPoint(x: 100, y: 100)
        }
        check("取消选中后调色不改变旧标注") { f in
            f.rectangle(); let before = f.document.state
            f.canvas.chooseTool(.rectangle); f.canvas.chooseMarkup(color: .markupPalette[2])
            let unchanged = f.document.state == before
            f.drag(CGPoint(x: 500, y: 100), CGPoint(x: 650, y: 200))
            return unchanged && f.document.state.objects.last?.style.color == .markupPalette[2]
        }
        check("Shift绘制正方形") { f in
            f.canvas.chooseTool(.rectangle); f.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 220), flags: .shift)
            return f.document.state.objects.first?.bounds == CGRect(x: 100, y: 100, width: 200, height: 200)
        }
        check("Shift拖动只沿主轴移动") { f in
            f.rectangle(); f.drag(CGPoint(x: 200, y: 170), CGPoint(x: 250, y: 180), flags: .shift)
            return f.document.state.objects.first?.start == CGPoint(x: 150, y: 100)
        }
        check("方向键及Shift方向键微调") { f in
            f.rectangle(); f.key(124); f.key(126, flags: .shift)
            return f.document.state.objects.first?.start == CGPoint(x: 101, y: 110)
        }
        check("箭头端点在绘制工具下可以直接调整") { f in
            f.canvas.chooseTool(.arrow); f.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
            f.drag(CGPoint(x: 300, y: 200), CGPoint(x: 350, y: 220))
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.end == CGPoint(x: 350, y: 220)
                && f.document.state.objects.first?.start == CGPoint(x: 100, y: 100)
        }
        check("重新选工具后旧箭头仍可移动") { f in
            f.canvas.chooseTool(.arrow); f.canvas.chooseMarkup(curved: false)
            f.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200)); f.canvas.chooseTool(.arrow)
            f.drag(CGPoint(x: 150, y: 125), CGPoint(x: 170, y: 145))
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.start == CGPoint(x: 120, y: 120)
        }
        check("文字输入撤销不会删除已有图形") { f in
            f.rectangle(); f.canvas.chooseTool(.text); f.mouse(.leftMouseDown, CGPoint(x: 450, y: 350))
            guard let input = f.canvas.textEditor else { return false }
            input.insertText("基础输入", replacementRange: NSRange(location: NSNotFound, length: 0)); input.breakUndoCoalescing()
            f.key(6, "z", flags: .control)
            let undone = input.string.isEmpty && f.document.state.objects.count == 1
            f.key(6, "z", flags: [.control, .shift])
            return undone && input.string == "基础输入" && f.document.state.objects.count == 1
        }
        check("文字输入菜单撤销状态独立于画布") { f in
            f.canvas.chooseTool(.text); f.mouse(.leftMouseDown, CGPoint(x: 450, y: 350))
            guard let input = f.canvas.textEditor else { return false }
            input.insertText("文字", replacementRange: NSRange(location: NSNotFound, length: 0)); input.breakUndoCoalescing()
            return f.editor.validateMenuItem(NSMenuItem(title: "撤销", action: #selector(ImageWindow.undo(_:)), keyEquivalent: "z"))
        }
        check("输入法候选期间撤销不碰画布") { f in
            f.rectangle(); let before = f.document.state
            f.canvas.chooseTool(.text); f.mouse(.leftMouseDown, CGPoint(x: 450, y: 350))
            guard let input = f.canvas.textEditor else { return false }
            input.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            f.key(6, "z", flags: .command)
            return input.hasMarkedText() && f.document.state == before
        }
        check("尺寸控制点可调整且一步撤销") { f in
            f.rectangle(); let before = f.document.state
            f.drag(CGPoint(x: 350, y: 250), CGPoint(x: 400, y: 280))
            let resized = f.document.state.objects.count == 1 && f.document.state.objects.first?.bounds == CGRect(x: 100, y: 100, width: 300, height: 180)
            f.editor.undo(nil); return resized && f.document.state == before
        }
        check("移动被限制在图片边界内") { f in
            f.rectangle(); f.drag(CGPoint(x: 200, y: 170), CGPoint(x: 790, y: 490))
            return f.document.state.objects.count == 1 && f.document.state.objects.first?.bounds == CGRect(x: 550, y: 350, width: 250, height: 150)
        }
        check("未选中大框不遮住里面的小框") { f in
            f.rectangle(); f.drag(CGPoint(x: 180, y: 140), CGPoint(x: 260, y: 210), flags: .option)
            let smallID = f.document.state.objects.last!.id
            f.canvas.chooseTool(.rectangle); f.drag(CGPoint(x: 180, y: 170), CGPoint(x: 190, y: 180))
            return f.document.state.objects.count == 2 && f.canvas.selectedID == smallID
                && f.document.state.objects.last?.start == CGPoint(x: 190, y: 150)
        }
        check("单击空白不产生零尺寸框") { f in
            f.canvas.chooseTool(.rectangle); f.drag(CGPoint(x: 450, y: 150), CGPoint(x: 450, y: 150))
            return f.document.state.objects.isEmpty && !f.document.canUndo
        }
        check("编号撤销恢复下一号") { f in
            f.canvas.chooseTool(.number)
            f.mouse(.leftMouseDown, CGPoint(x: 200, y: 150)); f.mouse(.leftMouseUp, CGPoint(x: 200, y: 150))
            f.key(6, "z", flags: .command)
            f.mouse(.leftMouseDown, CGPoint(x: 300, y: 150)); f.mouse(.leftMouseUp, CGPoint(x: 300, y: 150))
            return f.document.state.objects.map(\.number) == [1] && f.document.state.nextNumber == 2
        }
        check("选中改色可以撤销且不移动对象") { f in
            f.rectangle(); let before = f.document.state
            f.canvas.chooseMarkup(color: .markupPalette[2])
            let changed = f.document.state.objects.first?.style.color == .markupPalette[2]
            f.editor.undo(nil); return changed && f.document.state == before
        }
        check("普通文字输入框焦点不撤销图形") { f in
            f.rectangle(); let before = f.document.state
            let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 100, height: 24))
            f.window.contentView?.addSubview(field); f.window.makeFirstResponder(field)
            f.key(6, "z", flags: .command)
            return f.document.state == before
        }
        check("文字编辑Delete只删文字") { f in
            f.rectangle(); f.canvas.chooseTool(.text); f.mouse(.leftMouseDown, CGPoint(x: 450, y: 350))
            guard let input = f.canvas.textEditor else { return false }
            input.insertText("ABC", replacementRange: NSRange(location: NSNotFound, length: 0))
            f.key(51, "\u{7f}")
            return input.string == "AB" && f.document.state.objects.count == 1
        }
        do {
            let f = InteractionFixture(pinned: true); defer { f.close() }
            f.key(49, " "); f.rectangle(); let before = f.document.state
            f.key(49, " "); f.key(6, "z", flags: .command)
            checks["钉图查看状态不可误撤销标注"] = !f.canvas.editingEnabled && f.document.state == before
            f.key(49, " "); f.key(6, "z", flags: .command)
            checks["钉图编辑状态可以撤销标注"] = f.canvas.editingEnabled && f.document.state.objects.isEmpty
        }
        do {
            let f = InteractionFixture(withText: true); defer { f.close() }
            f.rectangle(); f.canvas.chooseTool(.select)
            await f.editor.recognitionForVerification?.value
            let r = f.canvas.contentRect
            let p = CGPoint(x: r.minX + 150 / 800 * r.width, y: r.minY + 193 / 500 * r.height)
            let hit = f.canvas.hitTest(f.canvas.convert(p, to: f.canvas.superview))
            checks["空心框内原图文字仍能选取"] = f.canvas.canStartTextSelection?(p) == true
                && f.canvas.canSelectText(at: p) && hit != nil && hit !== f.canvas
            f.editor.selectAll(nil); f.key(6, "z", flags: .command)
            checks["原图选字后仍可撤销标注"] = f.document.state.objects.isEmpty
        }
        let failed = checks.filter { !$0.value }.keys.sorted()
        for name in checks.keys.sorted() { print("\(checks[name]! ? "通过" : "失败")：\(name)") }
        let report: [String: Any] = ["checks": checks, "passed": failed.isEmpty, "general_clipboard_written": false,
                                     "scope": "自制样本；原生窗口事件与画布状态，不代表实体键盘或系统中文候选验收"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "build/interaction-tests.json"), options: .atomic)
        }
        print("共 \(checks.count) 项，失败 \(failed.count) 项")
        exit(failed.isEmpty ? 0 : 1)
    }
}
