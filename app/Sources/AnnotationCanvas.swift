import AppKit

@MainActor final class AnnotationCanvas: NSImageView {
    let document: AnnotationDocument
    let preferences: AppPreferences
    private(set) var tool = AnnotationTool.select
    private(set) var selectedID: UUID?
    private(set) var previewImage: CGImage?
    var editingEnabled = true
    var onBackgroundDrag:((NSEvent)->Void)?
    var canStartTextSelection:((CGPoint)->Bool)?
    var onDocumentChanged: (() -> Void)?
    var onPreviewBegin: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onStyleKey: ((CGFloat?, Int?) -> Void)?
    var onConfirm: (() -> Void)?
    var onSpace: (() -> Void)?
    var onExit: (() -> Void)?
    var onError: ((String) -> Void)?
    private(set) var textEditor: AnnotationTextView?
    private var textScroll: NSScrollView?
    private var textTopLeft: CGPoint?
    private var textMaximumWidth: CGFloat = 360
    var onZoom: ((CGFloat) -> Void)?
    private enum Drag { case draw, move(AnnotationObject), resize(AnnotationObject, SelectionHandle), endpoint(AnnotationObject, Bool), bend(AnnotationObject) }
    private var drag: Drag?
    private var anchor: CGPoint?
    private var draft: AnnotationObject?
    private var following: [AnnotationObject] = []
    private var fullDraftPreview = false
    var hasDraft: Bool { drag != nil || textEditor != nil }
    var selected: AnnotationObject? { document.state.objects.first { $0.id == selectedID } }
    var currentStyle: AnnotationStyle { (textEditor != nil ? draft?.style : nil) ?? selected?.style ?? newStyle(for: tool) }
    var currentTool: AnnotationTool { textEditor != nil ? .text : selected?.tool ?? tool }
    var imageSize: CGSize { CGSize(width: document.baseImage.width, height: document.baseImage.height) }
    var defaultStyleScale: CGFloat { AnnotationStyle.defaultScale(imageSize: imageSize, displayedWidth: contentRect.width) }
    private func newStyle(for tool: AnnotationTool) -> AnnotationStyle {
        preferences.annotationStyle(for: tool, scale: defaultStyleScale)
    }
    var contentRect: CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height)
    }
    init(document: AnnotationDocument, preferences: AppPreferences) {
        self.document = document; self.preferences = preferences
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown; imageAlignment = .alignCenter
        document.onChange = { [weak self] in
            guard let self else { return }
            if self.selected == nil { self.selectedID = nil }
            self.refreshPreview(); self.onDocumentChanged?()
        }
        refreshPreview()
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func canonical(_ point: CGPoint, clamp: Bool = false) -> CGPoint? {
        let rect = contentRect
        guard rect.width > 0, rect.height > 0, clamp || rect.contains(point) else { return nil }
        return CGPoint(x: min(imageSize.width, max(0, (point.x-rect.minX)*imageSize.width/rect.width)), y: min(imageSize.height, max(0, (point.y-rect.minY)*imageSize.height/rect.height)))
    }
    private func viewPoint(_ point: CGPoint) -> CGPoint {
        let rect = contentRect
        return CGPoint(x: rect.minX+point.x/imageSize.width*rect.width, y: rect.minY+point.y/imageSize.height*rect.height)
    }
    private var tolerance: CGFloat { 6 * imageSize.width / max(1, contentRect.width) }
    private func object(at point: CGPoint) -> AnnotationObject? { document.state.objects.reversed().first { $0.hit(point, tolerance: tolerance) } }
    func canSelectText(at point: CGPoint) -> Bool {
        guard !hasDraft, tool == .select, let p = canonical(point) else { return false }
        return !editingEnabled || object(at: p) == nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if textEditor != nil { return super.hitTest(point) }
        if !editingEnabled,onBackgroundDrag != nil,canStartTextSelection?(local) != true {return self}
        if editingEnabled && (tool != .select || selectedID != nil || (canonical(local).flatMap { object(at: $0) } != nil)) { return self }
        return super.hitTest(point)
    }
    func chooseTool(_ value: AnnotationTool) {
        if textEditor != nil && !finishTextEditing() { return }
        cancelGesture(); tool = value; selectedID = nil; needsDisplay = true; onSelectionChanged?()
    }
    func deselect() { selectedID = nil; needsDisplay = true; onSelectionChanged?() }
    private func refreshPreview() {
        var objects: [AnnotationObject]
        if let draft, let index = document.state.objects.firstIndex(where: { $0.id == draft.id }) {
            objects = Array(document.state.objects[..<index]); following = Array(document.state.objects.dropFirst(index+1))
        } else { objects = document.state.objects; following = [] }
        fullDraftPreview = draft != nil && (draft?.tool == .mask || following.contains(where: { $0.tool == .mask }))
        if fullDraftPreview, let draft { objects.append(draft); objects.append(contentsOf: following) }
        previewImage = AnnotationRenderer.render(base: document.baseImage, objects: objects)
        image = previewImage.map { NSImage(cgImage: $0, size: imageSize) }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !fullDraftPreview, let draft, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clip(to: contentRect)
            context.translateBy(x: contentRect.minX, y: contentRect.minY)
            context.scaleBy(x: contentRect.width/imageSize.width, y: contentRect.height/imageSize.height)
            if textEditor == nil { AnnotationRenderer.draw(draft, in: context) }
            for object in following { AnnotationRenderer.draw(object, in: context) }
            context.restoreGState()
        }
        guard editingEnabled, textEditor == nil, let object = draft ?? selected else { return }
        NSColor.systemBlue.setStroke()
        let topLeft = viewPoint(CGPoint(x: object.bounds.minX, y: object.bounds.minY))
        let bottomRight = viewPoint(CGPoint(x: object.bounds.maxX, y: object.bounds.maxY))
        let box = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x-topLeft.x, height: bottomRight.y-topLeft.y)
        let isLine = object.tool == .line || object.tool == .arrow
        if !isLine {
            let radius = min(4, box.width / 2, box.height / 2)
            let border = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
            border.setLineDash([4, 3], count: 2, phase: 0); border.stroke()
        }
        let points = isLine ? [viewPoint(object.start), viewPoint(object.end)] : SelectionHandle.allCases.map { viewPoint($0.point(in: object.bounds)) }
        if object.tool == .arrow {
            let center = viewPoint(object.arrowMidpoint)
            let handle = NSBezierPath(ovalIn:CGRect(x:center.x-4,y:center.y-4,width:8,height:8))
            NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); handle.stroke()
        }
        for point in points {
            let path = NSBezierPath(roundedRect: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6), xRadius: 1.5, yRadius: 1.5)
            NSColor.white.setFill(); path.fill(); NSColor.systemBlue.setStroke(); path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        if !editingEnabled {onBackgroundDrag?(event);return}
        guard let point = canonical(convert(event.locationInWindow, from: nil)) else { return }
        if textEditor != nil { _ = finishTextEditing(); return }
        window?.makeFirstResponder(self)
        // 已显示的控制点在当前工具下也应可拖动；空白区域继续绘制。
        if let object = selected {
            if object.tool == .line || object.tool == .arrow {
                if hypot(point.x-object.start.x, point.y-object.start.y) <= tolerance { begin(.endpoint(object, true), at: point, object: object); return }
                if hypot(point.x-object.end.x, point.y-object.end.y) <= tolerance { begin(.endpoint(object, false), at: point, object: object); return }
                if object.tool == .arrow, hypot(point.x-object.arrowMidpoint.x,point.y-object.arrowMidpoint.y) <= tolerance {
                    begin(.bend(object),at:point,object:object); return
                }
            } else if let handle = SelectionHandle.allCases.first(where: { hypot(point.x-$0.point(in: object.bounds).x, point.y-$0.point(in: object.bounds).y) <= tolerance }) {
                begin(.resize(object, handle), at: point, object: object); return
            }
        }
        if tool == .text {
            if let object = object(at: point), object.tool == .text { beginTextEditing(object, at: point) }
            else { beginTextEditing(nil, at: point) }
            return
        }
        // 已选几何对象可直接挪动；画笔、遮挡和连续编号仍保留原来的绘制方式。
        if [.arrow,.line,.rectangle,.ellipse].contains(tool), let object = selected, object.hit(point,tolerance:tolerance) {
            begin(.move(object),at:point,object:object); return
        }
        if tool == .select {
            if event.clickCount >= 2, let object = object(at: point), object.tool == .text { beginTextEditing(object, at: point); return }
            guard let object = object(at: point) else { deselect(); return }
            selectedID = object.id; onSelectionChanged?(); begin(.move(object), at: point, object: object)
        } else {
            let style = newStyle(for: tool)
            if tool == .number {
                let radius = min(style.width * 4, min(imageSize.width, imageSize.height)/2)
                let center = CGPoint(x: min(max(radius, point.x), imageSize.width-radius), y: min(max(radius, point.y), imageSize.height-radius))
                let object = AnnotationObject(tool: .number, style: style, start: CGPoint(x: center.x-radius, y: center.y-radius), end: CGPoint(x: center.x+radius, y: center.y+radius), number: document.state.nextNumber)
                var state = document.state; state.objects.append(object); state.nextNumber += 1
                selectedID = object.id; document.commit(state); onSelectionChanged?()
            } else {
                let object = AnnotationObject(tool: tool, style: style, start: point, end: point, points: tool == .pen || tool == .highlight || tool == .mask && style.maskBrush ? [point] : [])
                begin(.draw, at: point, object: object)
            }
        }
    }
    private func begin(_ mode: Drag, at point: CGPoint, object: AnnotationObject) {
        drag = mode; anchor = point; draft = object; onPreviewBegin?(); refreshPreview()
    }
    private func snapped(_ point: CGPoint, from start: CGPoint, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift) else { return point }
        let distance = hypot(point.x-start.x, point.y-start.y)
        let angle = (atan2(point.y-start.y, point.x-start.x) / (.pi/4)).rounded() * (.pi/4)
        return CGPoint(x: min(imageSize.width, max(0,start.x+cos(angle)*distance)), y: min(imageSize.height,max(0,start.y+sin(angle)*distance)))
    }
    override func mouseDragged(with event: NSEvent) {
        if !editingEnabled {onBackgroundDrag?(event);return}
        guard let drag, let anchor, let point = canonical(convert(event.locationInWindow, from: nil), clamp: true) else { return }
        switch drag {
        case .draw:
            guard var object = draft else { return }
            object.end = object.tool == .line || object.tool == .arrow ? snapped(point, from: anchor, event: event) : point
            if object.tool == .pen || object.tool == .highlight || object.tool == .mask && object.style.maskBrush {
                if let last = object.points.last, hypot(last.x-point.x,last.y-point.y) >= 0.5 { object.points.append(point) }
            }
            draft = object
        case .move(let original):
            let b = original.bounds
            let delta = CGPoint(x: min(max(point.x-anchor.x,-b.minX),imageSize.width-b.maxX), y: min(max(point.y-anchor.y,-b.minY),imageSize.height-b.maxY))
            draft = original.moved(by: delta)
        case .resize(let original, let handle):
            var value = original.resized(to: handle.resize(original.bounds, toward: point, canvas: imageSize, minimum: CGSize(width: 1, height: 1)))
            if value.tool == .text {
                let b = value.bounds
                guard b.width <= imageSize.width, b.height <= imageSize.height else { onError?("文字超出截图，请调小字号"); return }
                value = value.moved(by:CGPoint(x:min(max(0,b.minX),imageSize.width-b.width)-b.minX,y:min(max(0,b.minY),imageSize.height-b.height)-b.minY))
            }
            draft = value
        case .bend(let original):
            let middle = original.arrowMidpoint
            let target = CGPoint(x:middle.x+point.x-anchor.x,y:middle.y+point.y-anchor.y)
            var value = original
            value.curveControl = CGPoint(x:2*target.x-(original.start.x+original.end.x)/2,y:2*target.y-(original.start.y+original.end.y)/2)
            draft = boundedArrow(value,from:original)
        case .endpoint(var original, let first):
            let previous = original
            if first { original.start = snapped(point, from: original.end, event: event) }
            else { original.end = snapped(point, from: original.start, event: event) }
            // 移动端点时保留相对弦中点的弯曲偏移。
            if let control = previous.curveControl {
                original.curveControl = CGPoint(x:control.x+(original.start.x+original.end.x-previous.start.x-previous.end.x)/2,y:control.y+(original.start.y+original.end.y-previous.start.y-previous.end.y)/2)
            }
            draft = boundedArrow(original,from:previous)
        }
        if fullDraftPreview { refreshPreview() } else { needsDisplay = true }
    }
    // 弧线极值可能超出拖点位置；按实际路径边界限制，避免移出截图。
    private func boundedArrow(_ proposed: AnnotationObject, from original: AnnotationObject) -> AnnotationObject {
        guard proposed.tool == .arrow else { return proposed }
        func inside(_ object: AnnotationObject) -> Bool {
            let b = object.strokePath.boundingBoxOfPath
            return b.minX >= 0 && b.minY >= 0 && b.maxX <= imageSize.width && b.maxY <= imageSize.height
        }
        if inside(proposed) { return proposed }
        func mix(_ a: CGPoint,_ b: CGPoint,_ t: CGFloat) -> CGPoint { CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }
        let a = original.curveControl ?? original.arrowMidpoint
        let b = proposed.curveControl ?? proposed.arrowMidpoint
        var low: CGFloat = 0, high: CGFloat = 1, accepted = original
        for _ in 0..<24 {
            let t = (low+high)/2
            var value = original
            value.start = mix(original.start,proposed.start,t); value.end = mix(original.end,proposed.end,t)
            value.curveControl = mix(a,b,t)
            if inside(value) { accepted = value; low = t } else { high = t }
        }
        return accepted
    }
    override func mouseUp(with event: NSEvent) {
        if !editingEnabled {onBackgroundDrag?(event);return}
        guard textEditor == nil, let object = draft else { return }
        let valid: Bool
        if object.tool == .rectangle || object.tool == .ellipse || object.tool == .mask && !object.style.maskBrush { valid = abs(object.end.x-object.start.x) >= 1 && abs(object.end.y-object.start.y) >= 1 }
        else { valid = !object.points.isEmpty || hypot(object.end.x-object.start.x,object.end.y-object.start.y) >= 1 }
        draft = nil; drag = nil; anchor = nil; following = []
        if valid {
            var state = document.state
            if let index = state.objects.firstIndex(where: { $0.id == object.id }) { state.objects[index] = object }
            else { state.objects.append(object) }
            selectedID = object.id
            if !document.commit(state) { refreshPreview(); onDocumentChanged?() }
        } else { refreshPreview(); onDocumentChanged?() }
        onSelectionChanged?()
    }
    func cancelGesture() {
        if textEditor != nil { cancelTextEditing(); return }
        guard hasDraft else { return }
        draft = nil; drag = nil; anchor = nil; following = []; refreshPreview(); onDocumentChanged?()
    }
    func changeStyle(_ style: AnnotationStyle) {
        guard style.valid else { return }
        if let editor = textEditor {
            guard !editor.hasMarkedText() else { onError?("请先确认当前中文候选"); onSelectionChanged?(); return }
            draft?.style = style; updateTextEditorLayout(); onSelectionChanged?(); return
        }
        guard !hasDraft else { return }
        if let selectedID, let index = document.state.objects.firstIndex(where: { $0.id == selectedID }) {
            var state = document.state; state.objects[index].style = style
            if state.objects[index].tool == .number {
                let b = state.objects[index].bounds; let radius = min(style.width*4,min(imageSize.width,imageSize.height)/2)
                let center = CGPoint(x: min(max(radius,b.midX),imageSize.width-radius),y:min(max(radius,b.midY),imageSize.height-radius))
                state.objects[index].start = CGPoint(x: center.x-radius,y:center.y-radius); state.objects[index].end = CGPoint(x:center.x+radius,y:center.y+radius)
            }
            if state.objects[index].tool == .text {
                let old = state.objects[index].bounds
                let width = min(state.objects[index].textLayoutWidth,imageSize.width-old.minX)
                let size = AnnotationTextLayout.size(state.objects[index].text,style:style,maxWidth:width)
                guard size.height <= imageSize.height, size.width <= imageSize.width else { onError?("文字超出截图，请调小字号"); onSelectionChanged?(); return }
                let top = min(imageSize.height,max(size.height,old.maxY))
                state.objects[index].start = CGPoint(x:old.minX,y:top-size.height); state.objects[index].end = CGPoint(x:old.minX+size.width,y:top)
            }
            document.commit(state)
        } else { preferences.setAnnotationStyle(style, for: tool); onSelectionChanged?() }
    }
    @discardableResult func handleKey(_ event: NSEvent) -> Bool {
        guard textEditor == nil, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return false }
        if event.keyCode == 53 {
            if hasDraft { cancelGesture() }
            else if tool != .select { chooseTool(.select) }
            else if selectedID != nil { deselect() }
            else { onExit?() }
            return true
        }
        if event.keyCode == 49 { onSpace?(); return true }
        if event.isScreenshotReturn { onConfirm?(); return true }
        if !editingEnabled { return false }
        if let key = event.charactersIgnoringModifiers?.lowercased(), let next = AnnotationTool.allCases.first(where: { $0.key == key }) { chooseTool(next); return true }
        if event.keyCode == 51 || event.keyCode == 117, let id = selectedID {
            var state = document.state; state.objects.removeAll { $0.id == id }; selectedID = nil; document.commit(state); onSelectionChanged?(); return true
        }
        if let key = event.charactersIgnoringModifiers {
            if key == "[" || key == "]" { onStyleKey?(key == "[" ? -1 : 1,nil); return true }
            if let number = Int(key), (1...8).contains(number) { onStyleKey?(nil,number-1); return true }
        }
        if let selected, [123,124,125,126].contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var delta = CGPoint.zero
            switch event.keyCode { case 123: delta.x = -step; case 124: delta.x = step; case 125: delta.y = -step; default: delta.y = step }
            let b = selected.bounds
            delta.x = min(max(delta.x,-b.minX),imageSize.width-b.maxX); delta.y = min(max(delta.y,-b.minY),imageSize.height-b.maxY)
            var state = document.state; state.objects[state.objects.firstIndex(where: { $0.id == selected.id })!] = selected.moved(by: delta); document.commit(state); return true
        }
        return false
    }
    override func keyDown(with event: NSEvent) { if !handleKey(event) { super.keyDown(with: event) } }
    override func scrollWheel(with event: NSEvent) {
        if textEditor != nil { super.scrollWheel(with:event); return }
        if editingEnabled && (tool != .select || selectedID != nil) { onStyleKey?(event.scrollingDeltaY >= 0 ? 1 : -1,nil) }
        else { onZoom?(event.scrollingDeltaY >= 0 ? 1.05 : 0.95) }
    }
}

extension AnnotationCanvas {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize:oldSize); updateTextEditorLayout()
    }
    private func beginTextEditing(_ original: AnnotationObject?, at point: CGPoint) {
        guard imageSize.width >= 40, imageSize.height >= 32 else { onError?("截图太小，无法放入文字"); return }
        cancelGesture()
        var object = original ?? AnnotationObject(tool: .text, style: newStyle(for: .text), start: point, end: point)
        let previousText = object.text
        let topLeft = original.map { CGPoint(x:$0.bounds.minX,y:$0.bounds.maxY) } ?? CGPoint(x:min(point.x,imageSize.width-40),y:max(min(imageSize.height,point.y),min(100,imageSize.height)))
        textTopLeft = topLeft
        textMaximumWidth = min(original?.textLayoutWidth ?? 440,imageSize.width-topLeft.x)
        object.textLayoutWidth = textMaximumWidth
        object.text = ""
        object.start = CGPoint(x:topLeft.x,y:max(0,topLeft.y-min(180,topLeft.y)))
        object.end = CGPoint(x:topLeft.x+textMaximumWidth,y:topLeft.y)
        draft = object; selectedID = original?.id
        let editor = AnnotationTextView(frame:.zero)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.minSize = .zero; editor.maxSize = CGSize(width:1000000,height:1000000)
        editor.textContainer?.widthTracksTextView = true; editor.textContainer?.lineFragmentPadding = 0
        editor.insertionPointColor = .controlAccentColor; editor.string = previousText
        editor.onCommit = { [weak self] in _ = self?.finishTextEditing() }
        editor.onCancel = { [weak self] in self?.cancelTextEditing() }
        editor.onChange = { [weak self] in self?.onSelectionChanged?() }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false; scroll.borderType = .noBorder
        scroll.wantsLayer = true; scroll.layer?.borderColor = NSColor.controlAccentColor.cgColor; scroll.layer?.borderWidth = 1.5
        scroll.documentView = editor
        textEditor = editor; textScroll = scroll; addSubview(scroll)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("文字标注"); setAccessibilityChildren([scroll])
        onPreviewBegin?(); refreshPreview(); updateTextEditorLayout(); onSelectionChanged?()
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location:0,length:(previousText as NSString).length))
    }
    private func updateTextEditorLayout() {
        guard let editor = textEditor, let scroll = textScroll, let object = draft, let topLeft = textTopLeft else { return }
        let scale = contentRect.width/imageSize.width
        let height = min(max(120,object.bounds.height),topLeft.y)
        let bottomLeft = viewPoint(CGPoint(x:topLeft.x,y:topLeft.y-height))
        scroll.frame = CGRect(x:bottomLeft.x,y:bottomLeft.y,width:textMaximumWidth*scale,height:height*scale)
        editor.setFrameSize(CGSize(width:scroll.contentSize.width,height:max(scroll.contentSize.height,editor.frame.height)))
        editor.textContainerInset = CGSize(width:AnnotationTextLayout.inset*scale,height:AnnotationTextLayout.inset*scale)
        if !editor.hasMarkedText() {
            editor.font = NSFont.systemFont(ofSize:object.style.fontSize*scale,weight:object.style.bold ? .bold : .regular)
            editor.textColor = object.style.color.nsColor
            editor.drawsBackground = object.style.textBackground; editor.backgroundColor = object.style.backgroundColor.nsColor
        }
    }
    @discardableResult func finishTextEditing() -> Bool {
        guard let editor = textEditor, var object = draft, let topLeft = textTopLeft else { return true }
        guard !editor.hasMarkedText() else { onError?("请先确认当前中文候选"); return false }
        let text = editor.string
        if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            var state = document.state; state.objects.removeAll { $0.id == object.id }
            endTextEditing(); selectedID = nil
            if !document.commit(state) { refreshPreview(); onDocumentChanged?() }
            onSelectionChanged?(); return true
        }
        let size = AnnotationTextLayout.size(text,style:object.style,maxWidth:textMaximumWidth)
        guard size.height <= topLeft.y, size.width <= imageSize.width-topLeft.x else { onError?("文字超出截图，请缩短内容或调小字号"); return false }
        object.text = text; object.textLayoutWidth = textMaximumWidth
        object.start = CGPoint(x:topLeft.x,y:topLeft.y-size.height); object.end = CGPoint(x:topLeft.x+size.width,y:topLeft.y)
        endTextEditing(); selectedID = object.id
        var state = document.state
        if let index = state.objects.firstIndex(where:{$0.id == object.id}) { state.objects[index] = object } else { state.objects.append(object); preferences.setAnnotationStyle(object.style,for:.text) }
        if !document.commit(state) { refreshPreview(); onDocumentChanged?() }
        onSelectionChanged?(); return true
    }
    func cancelTextEditing() {
        guard textEditor != nil else { return }
        endTextEditing(); if selected == nil { selectedID = nil }
        refreshPreview(); onDocumentChanged?(); onSelectionChanged?()
    }
    private func endTextEditing() {
        textEditor?.inputContext?.discardMarkedText(); window?.makeFirstResponder(self)
        textScroll?.removeFromSuperview(); textScroll = nil; textEditor = nil; textTopLeft = nil
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("截图"); setAccessibilityChildren(nil)
        draft = nil; drag = nil; anchor = nil; following = []
    }
}
