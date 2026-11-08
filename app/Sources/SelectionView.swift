import AppKit

extension NSEvent {
    var isScreenshotReturn: Bool {
        (keyCode == 36 || keyCode == 76) && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }
}

enum SelectionAction: Equatable { case edit, copy, save, pin, annotate(AnnotationTool) }

@MainActor final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor final class SelectionView: NSView {
    let image: CGImage
    var automaticallyEdit=false
    var onConfirm: ((CGImage, NSRect, SelectionAction) -> Void)?
    var onCancel: (() -> Void)?
    var onWindowPick: ((WindowTarget) -> Void)?
    var windowTargets: [WindowTarget] = []
    private var hoveredWindow: WindowTarget?
    private var pendingWindow: WindowTarget?
    private var dragged = false
    private var windowStatus: String?
    private var anchor: NSPoint?
    private var selection = NSRect.zero
    private var selectionPixels: CGRect?
    private var previous = NSRect.zero
    private var moving = false
    private var resizing: SelectionHandle?
    private var pointer: NSPoint?
    private var pointerColor: SampledColor?
    private var mouseTracking: NSTrackingArea?
    private let actions = NSStackView()
    private lazy var actionPanel = FloatingControls(rows: [actions])

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
        for tool in [AnnotationTool.select,.arrow,.rectangle,.text,.pen,.mask,.highlight,.number] {
            let title = tool == .rectangle ? "画框" : tool.title
            let button = NSButton(title:title,target:self,action:#selector(editTool(_:)))
            button.tag = AnnotationTool.allCases.firstIndex(of:tool)!
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        for (title, action) in [("复制", #selector(copy(_:))), ("保存", #selector(saveDocument(_:))), ("钉住", #selector(pinSelection)), ("重新选择", #selector(reset)), ("取消", #selector(cancel))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        actions.spacing = 8
        actions.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        actionPanel.wantsLayer = true; actionPanel.layer?.cornerRadius = 8
        updateActionsAppearance()
        actionPanel.isHidden = true
        addSubview(actionPanel)
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateActionsAppearance()
    }
    private func updateActionsAppearance() {
        // 原生按钮带半透明底色，需使用稳定底板，避免截图亮度降低文字对比。
        effectiveAppearance.performAsCurrentDrawingAppearance {
            actionPanel.layer?.backgroundColor = CoreAppearance.surface.cgColor
        }
    }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func updateTrackingAreas() {
        if let mouseTracking { removeTrackingArea(mouseTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking); mouseTracking = tracking
        super.updateTrackingAreas()
    }
    override func selectAll(_ sender: Any?) { selectRegion(bounds);if automaticallyEdit {finish(.edit)} }

    func selectRegion(_ rect: CGRect) { updateSelection(rect); showActions() }
    func showWindowStatus(_ message: String?) { windowStatus = message; needsDisplay = true }

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    private func updateSelection(_ raw: CGRect) {
        if let pixels = CaptureGeometry.pixelRect(raw, canvas: bounds.size, image: imageSize) {
            selectionPixels = pixels
            selection = CaptureGeometry.viewRect(pixels, canvas: bounds.size, image: imageSize)
        } else { selection = .zero; selectionPixels = nil }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        let highlighted = selection.isEmpty ? hoveredWindow?.rect ?? .zero : selection
        context.saveGState()
        let outside = CGMutablePath()
        outside.addRect(bounds)
        if !highlighted.isEmpty { outside.addRect(highlighted) }
        context.addPath(outside)
        context.setFillColor(NSColor.black.withAlphaComponent(0.48).cgColor)
        context.drawPath(using: .eoFill)
        context.restoreGState()
        if !highlighted.isEmpty {
            CoreAppearance.captureBorder.setStroke()
            let border = NSBezierPath(rect: highlighted)
            border.lineWidth = CoreAppearance.captureBorderWidth
            border.stroke()
            for handle in selection.isEmpty ? [] : SelectionHandle.allCases {
                let point = handle.point(in: selection)
                let box = NSBezierPath(rect: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                NSColor.white.setFill(); box.fill(); CoreAppearance.captureBorder.setStroke(); box.stroke()
            }
        }
        if let pixels = selectionPixels {
            let text = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)]
            (text as NSString).draw(at: NSPoint(x: min(max(8, selection.minX), bounds.width - 150), y: min(bounds.height - 25, selection.maxY + 6)), withAttributes: attributes)
        }
        drawMagnifier(context)
        if let message = windowStatus ?? (hoveredWindow != nil && selection.isEmpty ? "单击截取窗口，拖动选择区域" : nil) {
            (message as NSString).draw(at: CGPoint(x: 12, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.windowBackgroundColor])
        }
    }
    private func pixel(at point: NSPoint) -> (Int, Int)? {
        guard bounds.contains(point) else { return nil }
        return (min(image.width - 1, Int(point.x * CGFloat(image.width) / bounds.width)),
                max(0, image.height - 1 - Int(point.y * CGFloat(image.height) / bounds.height)))
    }
    func updatePointer(_ point: NSPoint) {
        pointer = point
        hoveredWindow = selection.isEmpty ? WindowTarget.hit(point, in: windowTargets) : nil
        if let (x, y) = pixel(at: point) { pointerColor = PixelSampler.color(in: image, x: x, y: y) }
        else { pointerColor = nil }
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { updatePointer(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { pointer = nil; pointerColor = nil; hoveredWindow = nil; needsDisplay = true }
    private func drawMagnifier(_ context: CGContext) {
        guard let pointer, let color = pointerColor, let (x, y) = pixel(at: pointer) else { return }
        let size = CGSize(width: 130, height: 157)
        var origin = CGPoint(x: pointer.x + 20, y: pointer.y + 20)
        if origin.x + size.width > bounds.maxX { origin.x = pointer.x - size.width - 20 }
        if origin.y + size.height > bounds.maxY { origin.y = pointer.y - size.height - 20 }
        origin.x = max(0, min(origin.x, bounds.width - size.width))
        origin.y = max(0, min(origin.y, bounds.height - size.height))
        let panel = CGRect(origin: origin, size: size)
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()
        let sample = CGRect(x: panel.minX + 10, y: panel.minY + 37, width: 110, height: 110)
        let wanted = CGRect(x: x - 5, y: y - 5, width: 11, height: 11)
        let clipped = wanted.intersection(CGRect(origin: .zero, size: imageSize))
        if let magnified = image.cropping(to: clipped) {
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(magnified, in: CGRect(x: sample.minX + (clipped.minX - wanted.minX) * 10,
                y: sample.minY + (wanted.maxY - clipped.maxY) * 10, width: clipped.width * 10, height: clipped.height * 10))
            context.restoreGState()
        }
        NSColor.systemRed.setStroke()
        NSBezierPath(rect: CGRect(x: sample.midX - 5, y: sample.midY - 5, width: 10, height: 10)).stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
        (color.hex as NSString).draw(at: CGPoint(x: panel.minX + 10, y: panel.minY + 20), withAttributes: attributes)
        ("\(x), \(y) px" as NSString).draw(at: CGPoint(x: panel.minX + 10, y: panel.minY + 5), withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        previous = selection
        windowStatus = nil
        dragged = false
        pendingWindow = selection.isEmpty ? WindowTarget.hit(anchor!, in: windowTargets) : nil
        resizing = selection.isEmpty ? nil : SelectionHandle.allCases.first { handle in
            let point = handle.point(in: selection)
            return abs(point.x - anchor!.x) <= 7 && abs(point.y - anchor!.y) <= 7
        }
        moving = resizing == nil && !selection.isEmpty && selection.contains(anchor!)
        if event.clickCount == 2, moving { finish(.copy); return }
        updatePointer(anchor!)
        actionPanel.isHidden = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - anchor.x, point.y - anchor.y) > 3 { dragged = true; pendingWindow = nil }
        updatePointer(point)
        if let resizing {
            updateSelection(resizing.resize(previous, toward: point, canvas: bounds.size,
                minimum: CGSize(width: bounds.width / imageSize.width, height: bounds.height / imageSize.height)))
        } else if moving {
            var rect = previous.offsetBy(dx: point.x - anchor.x, dy: point.y - anchor.y)
            rect.origin.x = min(max(0, rect.minX), bounds.width - rect.width)
            rect.origin.y = min(max(0, rect.minY), bounds.height - rect.height)
            updateSelection(rect)
        } else {
            updateSelection(CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y), width: abs(point.x-anchor.x), height: abs(point.y-anchor.y)))
        }
    }
    override func mouseUp(with event: NSEvent) {
        if let anchor {
            let point = convert(event.locationInWindow, from: nil)
            if hypot(point.x - anchor.x, point.y - anchor.y) > 3 { dragged = true; pendingWindow = nil }
        }
        anchor = nil
        resizing = nil
        if !dragged, let target = pendingWindow {
            pendingWindow = nil
            onWindowPick?(target)
            return
        }
        pendingWindow = nil
        if automaticallyEdit,!selection.isEmpty {finish(.edit)} else {showActions()}
    }
    private func showActions() {
        actionPanel.isHidden = selection.isEmpty
        let size = actionPanel.panelSize(maxWidth: max(0, bounds.width - 24))
        actionPanel.frame = CGRect(x: max(12, min(selection.maxX - size.width, bounds.width - size.width - 12)),
                                   y: max(12, selection.minY - size.height - 12), width: size.width, height: size.height)
        actionPanel.fitContent()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { handleEscape(); return }
        if event.isScreenshotReturn { finish(.copy); return }
        if event.charactersIgnoringModifiers?.lowercased() == "c", event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            guard let color = pointerColor else { NSSound.beep(); return }
            let value = event.modifierFlags.contains(.shift) ? color.rgb : color.hex
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents(); pasteboard.setString(value, forType: .string)
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
            updateSelection(bounds); showActions(); return
        }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let dx = bounds.width / CGFloat(image.width) * step
        let dy = bounds.height / CGFloat(image.height) * step
        var rect = selection
        switch event.keyCode {
        case 123: rect.origin.x -= dx
        case 124: rect.origin.x += dx
        case 125: rect.origin.y -= dy
        case 126: rect.origin.y += dy
        default: super.keyDown(with: event); return
        }
        rect.origin.x = min(max(0, rect.minX), bounds.width - rect.width)
        rect.origin.y = min(max(0, rect.minY), bounds.height - rect.height)
        updateSelection(rect); showActions()
    }
    @objc func copy(_ sender: Any?) { finish(.copy) }
    @objc func saveDocument(_ sender: Any?) { finish(.save) }
    @objc func pinSelection() { finish(.pin) }
    @objc private func editTool(_ sender: NSButton) {
        guard AnnotationTool.allCases.indices.contains(sender.tag) else { return }
        finish(.annotate(AnnotationTool.allCases[sender.tag]))
    }
    @objc func confirm() { finish(.edit) }
    private func finish(_ action: SelectionAction) {
        guard let pixels = selectionPixels,
              let cropped = image.cropping(to: pixels) else { return }
        onConfirm?(cropped, window?.convertToScreen(selection) ?? selection, action)
    }
    @objc private func reset() { selection = .zero; selectionPixels = nil; actionPanel.isHidden = true; needsDisplay = true }
    override func cancelOperation(_ sender: Any?) { handleEscape() }
    private func handleEscape() {
        pendingWindow = nil
        if anchor != nil { anchor = nil; resizing = nil; moving = false; selectRegion(previous) }
        else if !selection.isEmpty { reset() }
        else { cancel() }
    }
    @objc private func cancel() { onCancel?() }
}
