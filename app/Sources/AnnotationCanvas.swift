import AppKit

@MainActor final class AnnotationCanvas: NSImageView {
    let document: AnnotationDocument
    let preferences: AppPreferences
    private(set) var tool = AnnotationTool.select
    private(set) var selectedID: UUID?
    private(set) var previewImage: CGImage?
    var editingEnabled = true
    var onDocumentChanged: (() -> Void)?
    var onPreviewBegin: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onStyleKey: ((CGFloat?, Int?) -> Void)?
    var onConfirm: (() -> Void)?
    var onSpace: (() -> Void)?
    var onExit: (() -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    private enum Drag { case draw, move(AnnotationObject), resize(AnnotationObject, SelectionHandle), endpoint(AnnotationObject, Bool) }
    private var drag: Drag?
    private var anchor: CGPoint?
    private var draft: AnnotationObject?
    private var following: [AnnotationObject] = []
    private var fullDraftPreview = false
    var hasDraft: Bool { drag != nil }
    var selected: AnnotationObject? { document.state.objects.first { $0.id == selectedID } }
    var currentStyle: AnnotationStyle { selected?.style ?? preferences.annotationStyle(for: tool) }
    var currentTool: AnnotationTool { selected?.tool ?? tool }
    var imageSize: CGSize { CGSize(width: document.baseImage.width, height: document.baseImage.height) }
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
        if editingEnabled && (tool != .select || selectedID != nil || (canonical(local).flatMap { object(at: $0) } != nil)) { return self }
        return super.hitTest(point)
    }
    func chooseTool(_ value: AnnotationTool) {
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
            AnnotationRenderer.draw(draft, in: context)
            for object in following { AnnotationRenderer.draw(object, in: context) }
            context.restoreGState()
        }
        guard editingEnabled, let object = draft ?? selected else { return }
        NSColor.systemBlue.setStroke()
        let topLeft = viewPoint(CGPoint(x: object.bounds.minX, y: object.bounds.minY))
        let bottomRight = viewPoint(CGPoint(x: object.bounds.maxX, y: object.bounds.maxY))
        let box = CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x-topLeft.x, height: bottomRight.y-topLeft.y)
        let border = NSBezierPath(rect: box); border.setLineDash([4, 3], count: 2, phase: 0); border.stroke()
        let points = object.tool == .line || object.tool == .arrow ? [viewPoint(object.start), viewPoint(object.end)] : SelectionHandle.allCases.map { viewPoint($0.point(in: object.bounds)) }
        for point in points {
            let path = NSBezierPath(rect: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6))
            NSColor.white.setFill(); path.fill(); NSColor.systemBlue.setStroke(); path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard editingEnabled, let point = canonical(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        if tool == .select {
            if let object = selected {
                if object.tool == .line || object.tool == .arrow {
                    if hypot(point.x-object.start.x, point.y-object.start.y) <= tolerance { begin(.endpoint(object, true), at: point, object: object); return }
                    if hypot(point.x-object.end.x, point.y-object.end.y) <= tolerance { begin(.endpoint(object, false), at: point, object: object); return }
                } else if let handle = SelectionHandle.allCases.first(where: { hypot(point.x-$0.point(in: object.bounds).x, point.y-$0.point(in: object.bounds).y) <= tolerance }) {
                    begin(.resize(object, handle), at: point, object: object); return
                }
            }
            guard let object = object(at: point) else { deselect(); return }
            selectedID = object.id; onSelectionChanged?(); begin(.move(object), at: point, object: object)
        } else {
            let style = preferences.annotationStyle(for: tool)
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
        case .resize(let original, let handle): draft = original.resized(to: handle.resize(original.bounds, toward: point, canvas: imageSize, minimum: CGSize(width: 1, height: 1)))
        case .endpoint(var original, let first):
            if first { original.start = snapped(point, from: original.end, event: event) }
            else { original.end = snapped(point, from: original.start, event: event) }
            draft = original
        }
        if fullDraftPreview { refreshPreview() } else { needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        guard let object = draft else { return }
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
        guard hasDraft else { return }
        draft = nil; drag = nil; anchor = nil; following = []; refreshPreview(); onDocumentChanged?()
    }
    func changeStyle(_ style: AnnotationStyle) {
        guard !hasDraft, style.valid else { return }
        if let selectedID, let index = document.state.objects.firstIndex(where: { $0.id == selectedID }) {
            var state = document.state; state.objects[index].style = style
            if state.objects[index].tool == .number {
                let b = state.objects[index].bounds; let radius = min(style.width*4,min(imageSize.width,imageSize.height)/2)
                let center = CGPoint(x: min(max(radius,b.midX),imageSize.width-radius),y:min(max(radius,b.midY),imageSize.height-radius))
                state.objects[index].start = CGPoint(x: center.x-radius,y:center.y-radius); state.objects[index].end = CGPoint(x:center.x+radius,y:center.y+radius)
            }
            document.commit(state)
        } else { preferences.setAnnotationStyle(style, for: tool); onSelectionChanged?() }
    }
    @discardableResult func handleKey(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return false }
        if event.keyCode == 53 {
            if hasDraft { cancelGesture() }
            else if tool != .select { chooseTool(.select) }
            else if selectedID != nil { deselect() }
            else { onExit?() }
            return true
        }
        if event.keyCode == 49 { onSpace?(); return true }
        if event.keyCode == 36 { onConfirm?(); return true }
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
        if editingEnabled && (tool != .select || selectedID != nil) { onStyleKey?(event.scrollingDeltaY >= 0 ? 1 : -1,nil) }
        else { onZoom?(event.scrollingDeltaY >= 0 ? 1.05 : 0.95) }
    }
}
