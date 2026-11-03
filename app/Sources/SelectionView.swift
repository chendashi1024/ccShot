import AppKit

enum SelectionAction { case edit, copy, save, pin }

@MainActor final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor final class SelectionView: NSView {
    let image: CGImage
    var onConfirm: ((CGImage, NSRect, SelectionAction) -> Void)?
    var onCancel: (() -> Void)?
    private var anchor: NSPoint?
    private var selection = NSRect.zero
    private var previous = NSRect.zero
    private var moving = false
    private let actions = NSStackView()

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
        for (title, action) in [("重新选择", #selector(reset)), ("取消", #selector(cancel)), ("完成", #selector(confirm))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        actions.spacing = 8
        actions.isHidden = true
        addSubview(actions)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func selectAll(_ sender: Any?) { selectRegion(bounds) }

    func selectRegion(_ rect: CGRect) { updateSelection(rect); showActions() }

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    private func updateSelection(_ raw: CGRect) {
        if let pixels = CaptureGeometry.pixelRect(raw, canvas: bounds.size, image: imageSize) {
            selection = CaptureGeometry.viewRect(pixels, canvas: bounds.size, image: imageSize)
        } else { selection = .zero }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        context.saveGState()
        let outside = CGMutablePath()
        outside.addRect(bounds)
        if !selection.isEmpty { outside.addRect(selection) }
        context.addPath(outside)
        context.setFillColor(NSColor.black.withAlphaComponent(0.48).cgColor)
        context.drawPath(using: .eoFill)
        context.restoreGState()
        guard !selection.isEmpty else { return }
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()
        if let pixels = CaptureGeometry.pixelRect(selection, canvas: bounds.size, image: imageSize) {
            let text = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)]
            (text as NSString).draw(at: NSPoint(x: min(max(8, selection.minX), bounds.width - 150), y: min(bounds.height - 25, selection.maxY + 6)), withAttributes: attributes)
        }
    }
    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        previous = selection
        moving = !selection.isEmpty && selection.contains(anchor!)
        actions.isHidden = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        if moving {
            var rect = previous.offsetBy(dx: point.x - anchor.x, dy: point.y - anchor.y)
            rect.origin.x = min(max(0, rect.minX), bounds.width - rect.width)
            rect.origin.y = min(max(0, rect.minY), bounds.height - rect.height)
            updateSelection(rect)
        } else {
            updateSelection(CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y), width: abs(point.x-anchor.x), height: abs(point.y-anchor.y)))
        }
    }
    override func mouseUp(with event: NSEvent) {
        anchor = nil
        showActions()
    }
    private func showActions() {
        actions.isHidden = selection.isEmpty
        actions.frame.size = actions.fittingSize
        actions.frame.origin = NSPoint(x: min(max(8, selection.maxX - actions.frame.width), bounds.width - actions.frame.width - 8), y: max(8, selection.minY - actions.frame.height - 10))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel(); return }
        if event.keyCode == 36 { confirm(); return }
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
    func pinSelection() { finish(.pin) }
    @objc func confirm() { finish(.edit) }
    private func finish(_ action: SelectionAction) {
        guard let pixels = CaptureGeometry.pixelRect(selection, canvas: bounds.size, image: imageSize),
              let cropped = image.cropping(to: pixels) else { return }
        onConfirm?(cropped, window?.convertToScreen(selection) ?? selection, action)
    }
    @objc private func reset() { selection = .zero; actions.isHidden = true; needsDisplay = true }
    @objc private func cancel() { onCancel?() }
}
