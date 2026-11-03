import AppKit
import VisionKit
import UniformTypeIdentifiers

@MainActor final class AnnotationWindow: NSWindow {
    var handleCanvasKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if handleCanvasKey?(event) != true { super.keyDown(with: event) }
    }
}

@MainActor final class StyleSlider: NSSlider {
    var beginTracking: (() -> Void)?
    var endTracking: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        beginTracking?(); super.mouseDown(with: event); endTracking?()
    }
}

@MainActor final class ImageWindow: NSWindowController, NSWindowDelegate, ImageAnalysisOverlayViewDelegate, NSMenuItemValidation, NSTextFieldDelegate {
    let annotationDocument: AnnotationDocument
    let pinned: Bool
    let canvas: AnnotationCanvas
    private let overlay = ImageAnalysisOverlayView()
    private let status = NSTextField(labelWithString: "正在识别文字…")
    private let toolRow = NSStackView()
    private let viewerRow = NSStackView()
    private var styleButton: NSButton!
    private var copyButton: NSButton!
    private var viewerCopyButton: NSButton!
    private var pinButton: NSButton!
    private var saveButton: NSButton!
    private var donePinButton: NSButton!
    private var styleExpanded = false
    private var viewingFrame: CGRect?
    private let styleRow = NSStackView()
    private let optionRow = NSStackView()
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private let widthSlider = StyleSlider(value: 4, minValue: 1, maxValue: 80, target: nil, action: nil)
    private let widthTitle = NSTextField(labelWithString: "粗细")
    private var presetButtons: [NSButton] = []
    private var colorControls: [NSView] = []
    private let maskPicker = NSSegmentedControl(labels: ["马赛克", "模糊"], trackingMode: .selectOne, target: nil, action: nil)
    private let maskMode = NSSegmentedControl(labels: ["框选", "涂抹"], trackingMode: .selectOne, target: nil, action: nil)
    private let brushWidth = StyleSlider(value: 32, minValue: 1, maxValue: 80, target: nil, action: nil)
    private let brushLabel = NSTextField(labelWithString: "笔宽")
    private let widthLabel = NSTextField(labelWithString: "4 px")
    private let colorWell = NSColorWell()
    private let fillButton = NSSegmentedControl(labels: ["描边", "半透明", "实心"], trackingMode: .selectOne, target: nil, action: nil)
    private let dashButton = NSButton(checkboxWithTitle: "虚线", target: nil, action: nil)
    private let cornerSlider = StyleSlider(value: 0, minValue: 0, maxValue: 80, target: nil, action: nil)
    private let cornerLabel = NSTextField(labelWithString: "圆角")
    private let arrowPicker = NSSegmentedControl(labels: ["实心", "开口", "双头"], trackingMode: .selectOne, target: nil, action: nil)
    private let numberLabel = NSTextField(labelWithString: "下一号")
    private let numberField = NSTextField(string: "1")
    private let boldButton = NSButton(checkboxWithTitle: "加粗", target: nil, action: nil)
    private let textBackground = NSButton(checkboxWithTitle: "底色", target: nil, action: nil)
    private let backgroundWell = NSColorWell()
    private var finishTextButton: NSButton!
    private var cancelTextButton: NSButton!
    private let editButton = NSButton(title: "标注", target: nil, action: nil)
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var editing: Bool
    private var baseRegionsTask: Task<[CGRect], Error>?
    private var recognition: Task<Void, Never>?
    private var generation = 0
    private var closed = false
    private let preferences: AppPreferences
    var onClose: (() -> Void)?
    var onPin: ((AnnotationDocument) -> Void)?

    convenience init(image: CGImage, pinned: Bool, preferences: AppPreferences = .shared) {
        self.init(annotationDocument: AnnotationDocument(image: image), pinned: pinned, preferences: preferences)
    }
    init(annotationDocument: AnnotationDocument, pinned: Bool, preferences: AppPreferences = .shared) {
        self.annotationDocument = annotationDocument; self.pinned = pinned; self.preferences = preferences
        canvas = AnnotationCanvas(document: annotationDocument, preferences: preferences)
        editing = !pinned
        let ratio = CGFloat(annotationDocument.baseImage.height) / CGFloat(annotationDocument.baseImage.width)
        let width: CGFloat = min(pinned ? 900 : 1040, max(pinned ? 420 : 880, CGFloat(annotationDocument.baseImage.width)))
        let height = min(780, max(pinned ? 260 : 360, width * ratio + 100))
        let window = AnnotationWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = pinned ? "CcShot · 钉图" : "CcShot"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: pinned ? 420 : 880, height: pinned ? 260 : 300)
        window.backgroundColor = CoreAppearance.surface
        if pinned { window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        super.init(window: window)
        window.delegate = self
        let root = CoreSurfaceView(); window.contentView = root
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        overlay.delegate = self; overlay.trackingImageView = canvas
        overlay.preferredInteractionTypes = .textSelection
        overlay.autoresizingMask = [.width, .height]; canvas.addSubview(overlay)
        buildStyles()
        undoButton = iconButton("arrow.uturn.backward", "撤销（⌘Z）", #selector(undo(_:)))
        redoButton = iconButton("arrow.uturn.forward", "重做（⌘⇧Z）", #selector(redo(_:)))
        styleButton = button("样式",#selector(toggleStyle)); styleButton.setAccessibilityLabel("样式")
        toolRow.addArrangedSubview(styleButton); toolRow.addArrangedSubview(undoButton); toolRow.addArrangedSubview(redoButton)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant:8).isActive = true; toolRow.addArrangedSubview(spacer)
        pinButton = button("钉住",#selector(pinImage)); saveButton = button("保存",#selector(saveImage)); copyButton = button("复制",#selector(copy(_:)))
        donePinButton = button("完成",#selector(toggleEditing))
        for value in [donePinButton,pinButton,saveButton,copyButton] { toolRow.addArrangedSubview(value!) }
        finishTextButton = button("完成文字",#selector(finishText)); cancelTextButton = button("取消",#selector(cancelText))
        finishTextButton.toolTip = "完成文字（⌘Return）"; cancelTextButton.toolTip = "取消文字（Esc）"
        toolRow.addArrangedSubview(finishTextButton); toolRow.addArrangedSubview(cancelTextButton)
        editButton.target = self; editButton.action = #selector(toggleEditing); editButton.bezelStyle = .rounded; editButton.font = .systemFont(ofSize:14)
        viewerCopyButton = button("复制",#selector(copy(_:)))
        viewerRow.spacing = 8
        for view in [editButton,viewerCopyButton,button("关闭",#selector(closeImage))] { viewerRow.addArrangedSubview(view!) }
        canvas.menu = makeContextMenu()
        status.textColor = .labelColor; status.font = .systemFont(ofSize:13)
        let stack = NSStackView(views:[toolRow,viewerRow,styleRow,optionRow,canvas,status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            toolRow.widthAnchor.constraint(equalTo:stack.widthAnchor), canvas.widthAnchor.constraint(equalTo: stack.widthAnchor), canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        canvas.onError = { [weak self] message in self?.status.stringValue = message }
        canvas.onPreviewBegin = { [weak self] in self?.invalidateRecognition() }
        canvas.onDocumentChanged = { [weak self] in self?.updateControls(); self?.recognize() }
        canvas.onSelectionChanged = { [weak self] in self?.updateControls() }
        canvas.onStyleKey = { [weak self] delta, color in self?.changeStyleKey(delta, color) }
        canvas.onConfirm = { [weak self] in self?.copyImage() }
        canvas.onSpace = { [weak self] in if self?.pinned == true { self?.toggleEditing() } else { self?.copyImage() } }
        canvas.onExit = { [weak self] in self?.cancelOperation(nil) }
        canvas.onZoom = { [weak self] factor in self?.zoom(factor) }
        updateControls(); window.center(); showWindow(nil); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.handleCanvasKey = { [weak self] event in self?.canvas.handleKey(event) ?? false }
        window.makeFirstResponder(canvas)
        root.layoutSubtreeIfNeeded(); overlay.frame = canvas.bounds; overlay.setContentsRectNeedsUpdate()
        recognize()
    }
    required init?(coder: NSCoder) { nil }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title:title,target:self,action:action); button.bezelStyle = .rounded; button.font = .systemFont(ofSize:14); button.heightAnchor.constraint(greaterThanOrEqualToConstant:28).isActive = true; return button
    }
    private func iconButton(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let value = button("",action); value.image = NSImage(systemSymbolName:symbol,accessibilityDescription:title); value.imagePosition = .imageOnly
        value.toolTip = title; value.setAccessibilityLabel(title); value.widthAnchor.constraint(equalToConstant:28).isActive = true; return value
    }
    private func buildStyles() {
        toolRow.spacing = 4; styleRow.spacing = 8; optionRow.spacing = 10
        for tool in [AnnotationTool.select,.arrow,.rectangle,.text,.pen,.mask,.highlight,.number] {
            let index = AnnotationTool.allCases.firstIndex(of:tool)!
            let title = tool == .rectangle ? "画框" : tool == .mask ? "遮挡" : tool.title
            let value = button(title, #selector(chooseTool(_:))); value.tag = index; value.setButtonType(.pushOnPushOff)
            value.toolTip = "\(title)（\(tool.key.uppercased())）"; toolButtons[tool] = value; toolRow.addArrangedSubview(value)
        }
        widthSlider.target = self; widthSlider.action = #selector(changeWidth(_:)); widthSlider.isContinuous = true
        widthSlider.widthAnchor.constraint(equalToConstant: 105).isActive = true
        widthLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        styleRow.addArrangedSubview(widthTitle); styleRow.addArrangedSubview(widthSlider); styleRow.addArrangedSubview(widthLabel)
        for width in [2, 4, 8, 16] { let value = button("\(width)", #selector(widthPreset(_:))); value.tag = width; presetButtons.append(value); styleRow.addArrangedSubview(value) }
        for (index, color) in AnnotationColor.palette.enumerated() {
            let value = NSButton(title: "●", target: self, action: #selector(palette(_:))); value.isBordered = false
            value.attributedTitle = NSAttributedString(string: "●", attributes: [.foregroundColor: color.nsColor, .font: NSFont.systemFont(ofSize: 22)])
            value.tag = index; value.toolTip = "颜色 \(index+1)"; value.setAccessibilityLabel("预设颜色 \(index+1)")
            value.widthAnchor.constraint(equalToConstant:26).isActive = true; value.heightAnchor.constraint(equalToConstant:26).isActive = true
            value.wantsLayer = true; value.layer?.cornerRadius = 13; value.layer?.borderWidth = 0.75; value.layer?.borderColor = NSColor.gray.cgColor; colorControls.append(value); styleRow.addArrangedSubview(value)
        }
        colorWell.target = self; colorWell.action = #selector(changeColor(_:)); colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true; colorControls.append(colorWell); styleRow.addArrangedSubview(colorWell)
        fillButton.target = self; fillButton.action = #selector(changeOptions)
        dashButton.target = self; dashButton.action = #selector(changeOptions)
        arrowPicker.target = self; arrowPicker.action = #selector(changeOptions)
        cornerSlider.target = self; cornerSlider.action = #selector(changeCorner(_:)); cornerSlider.isContinuous = true
        cornerSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        numberField.delegate = self; numberField.target = self; numberField.action = #selector(changeNumber); numberField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        maskPicker.target = self; maskPicker.action = #selector(changeMask)
        maskMode.target = self; maskMode.action = #selector(changeMask)
        brushWidth.target = self; brushWidth.action = #selector(changeBrush(_:)); brushWidth.isContinuous = true
        brushWidth.widthAnchor.constraint(equalToConstant: 90).isActive = true
        boldButton.target = self; boldButton.action = #selector(changeTextStyle)
        textBackground.target = self; textBackground.action = #selector(changeTextStyle)
        backgroundWell.target = self; backgroundWell.action = #selector(changeTextStyle); backgroundWell.widthAnchor.constraint(equalToConstant:40).isActive = true
        for view in [boldButton, textBackground, backgroundWell, fillButton, dashButton, cornerLabel, cornerSlider, arrowPicker, numberLabel, numberField, maskPicker, maskMode, brushLabel, brushWidth] as [NSView] { optionRow.addArrangedSubview(view) }
        for slider in [widthSlider, cornerSlider, brushWidth] {
            slider.beginTracking = { [weak self] in if self?.canvas.selected != nil { self?.annotationDocument.beginTransaction() } }
            slider.endTracking = { [weak self] in if self?.annotationDocument.inTransaction == true { self?.annotationDocument.endTransaction() } }
        }
    }
    private func updateControls() {
        let tool = canvas.currentTool, style = canvas.currentStyle
        canvas.editingEnabled = editing
        toolRow.isHidden = !editing
        styleRow.isHidden = !editing || tool == .select || !styleExpanded
        viewerRow.isHidden = !pinned || editing
        window?.minSize = CGSize(width:editing ? 880 : 420,height:styleRow.isHidden ? (editing ? 300 : 260) : 480)
        styleButton.isEnabled = editing && tool != .select
        styleButton.title = "样式"
        styleButton.toolTip = "\(tool.title)样式"
        for (tool, button) in toolButtons {
            let selected = tool == canvas.tool; button.state = selected ? .on : .off
            button.bezelColor = selected ? CoreAppearance.accent : nil; button.contentTintColor = selected ? .white : .labelColor
        }
        let width = tool == .text ? style.fontSize : tool == .mask ? style.maskStrength : style.width
        widthTitle.stringValue = tool == .text ? "字号" : tool == .mask ? "强度" : "粗细"
        widthSlider.minValue = tool == .text ? 8 : tool == .mask ? 4 : 1; widthSlider.maxValue = tool == .text ? 200 : 80
        widthSlider.doubleValue = Double(width); widthLabel.stringValue = "\(Int(width)) px";
        let presetWidths = tool == .text ? [16,24,32,48] : tool == .mask ? [8,16,32,64] : [2,4,8,16]
        for (button, value) in zip(presetButtons,presetWidths) { button.title = "\(value)"; button.tag = value }
        for control in colorControls { control.isHidden = tool == .mask }
        maskPicker.isHidden = tool != .mask; maskMode.isHidden = tool != .mask || canvas.selected != nil
        maskPicker.selectedSegment = style.maskEffect == .pixelate ? 0 : 1; maskMode.selectedSegment = style.maskBrush ? 1 : 0
        brushWidth.isHidden = tool != .mask || !style.maskBrush; brushLabel.isHidden = brushWidth.isHidden; brushWidth.doubleValue = Double(style.width)
         colorWell.color = style.color.nsColor
        finishTextButton.isHidden = canvas.textEditor == nil; cancelTextButton.isHidden = canvas.textEditor == nil
        boldButton.isHidden = tool != .text; textBackground.isHidden = tool != .text
        backgroundWell.isHidden = tool != .text || !style.textBackground
        boldButton.state = style.bold ? .on : .off; textBackground.state = style.textBackground ? .on : .off; backgroundWell.color = style.backgroundColor.nsColor
        fillButton.selectedSegment = style.filled ? (style.fillOpacity < 1 ? 1 : 2) : 0; dashButton.state = style.dashed ? .on : .off
        cornerSlider.doubleValue = Double(style.cornerRadius)
        arrowPicker.selectedSegment = ArrowHead.allCases.firstIndex(of: style.arrowHead) ?? 0
        fillButton.isHidden = ![.rectangle, .ellipse].contains(tool)
        dashButton.isHidden = ![.rectangle, .ellipse, .arrow, .line].contains(tool) || style.filled && [.rectangle, .ellipse].contains(tool)
        cornerLabel.isHidden = tool != .rectangle; cornerSlider.isHidden = tool != .rectangle
        arrowPicker.isHidden = tool != .arrow
        numberLabel.isHidden = tool != .number; numberField.isHidden = tool != .number
        numberLabel.stringValue = canvas.selected == nil ? "下一号" : "编号"
        if window?.firstResponder !== numberField.currentEditor() { numberField.stringValue = "\(canvas.selected?.number ?? annotationDocument.state.nextNumber)" }
        optionRow.isHidden = styleRow.isHidden || [.pen,.highlight].contains(tool)
        let input = canvas.textEditor
        pinButton.isHidden = pinned || input != nil; saveButton.isHidden = input != nil; copyButton.isHidden = input != nil; donePinButton.isHidden = !pinned || input != nil
        if let input {
            undoButton.isEnabled = input.undoManager?.canUndo == true && !input.hasMarkedText()
            redoButton.isEnabled = input.undoManager?.canRedo == true && !input.hasMarkedText()
        } else {
            undoButton.isEnabled = annotationDocument.canUndo && !canvas.hasDraft && !annotationDocument.inTransaction
            redoButton.isEnabled = annotationDocument.canRedo && !canvas.hasDraft && !annotationDocument.inTransaction
        }
        overlay.isHidden = canvas.hasDraft || canvas.tool != .select || canvas.selected != nil
        updateCopyTitle()
        canvas.needsDisplay = true
    }
    private func updateCopyTitle() {
        let title = !overlay.isHidden && overlay.hasActiveTextSelection && !overlay.selectedText.isEmpty ? "复制文字" : "复制"
        copyButton?.title = title; viewerCopyButton?.title = title
        let help = title == "复制文字" ? "复制选中的文字" : "复制当前图片"; copyButton?.toolTip = help; viewerCopyButton?.toolTip = help
        canvas.menu = makeContextMenu()
    }
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        if !overlay.isHidden && !overlay.selectedText.isEmpty { menu.addItem(withTitle:"复制文字",action:#selector(copySelectedText),keyEquivalent:"").target = self }
        if !overlay.text.isEmpty { menu.addItem(withTitle:"复制全部文字",action:#selector(copyAllText),keyEquivalent:"").target = self }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for (title,action) in [("复制图片",#selector(copyImage)),("保存图片…",#selector(saveImage))] { menu.addItem(withTitle:title,action:action,keyEquivalent:"").target = self }
        if !pinned { menu.addItem(withTitle:"钉住",action:#selector(pinImage),keyEquivalent:"").target = self }
        else {
            let opacity = NSMenuItem(title:"透明度",action:nil,keyEquivalent:""); opacity.submenu = NSMenu()
            for value in [100,75,50,25] { let item = NSMenuItem(title:"\(value)%",action:#selector(opacityPreset(_:)),keyEquivalent:""); item.tag = value; item.target = self; opacity.submenu?.addItem(item) }
            menu.addItem(opacity)
        }
        return menu
    }
    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) { updateCopyTitle() }
    @objc private func toggleStyle() {
        styleExpanded.toggle()
        if styleExpanded, let window, window.frame.height < 480 { var frame = window.frame; frame.origin.y -= 480-frame.height; frame.size.height = 480; setVisibleFrame(frame) }
        updateControls()
    }
    @objc private func closeImage() { close() }
    @objc private func opacityPreset(_ sender: NSMenuItem) { window?.alphaValue = Double(sender.tag)/100 }
    @objc private func chooseTool(_ sender: NSButton) { canvas.chooseTool(AnnotationTool.allCases[sender.tag]); if canvas.textEditor == nil { window?.makeFirstResponder(canvas) } }
    @objc private func changeWidth(_ sender: NSSlider) { var style = canvas.currentStyle; if canvas.currentTool == .text { style.fontSize = CGFloat(sender.doubleValue.rounded()) } else if canvas.currentTool == .mask { style.maskStrength = CGFloat(sender.doubleValue.rounded()) } else { style.width = CGFloat(sender.doubleValue.rounded()) }; canvas.changeStyle(style) }
    @objc private func widthPreset(_ sender: NSButton) { var style = canvas.currentStyle; if canvas.currentTool == .text { style.fontSize = CGFloat(sender.tag) } else if canvas.currentTool == .mask { style.maskStrength = max(4,CGFloat(sender.tag)) } else { style.width = CGFloat(sender.tag) }; canvas.changeStyle(style) }
    @objc private func palette(_ sender: NSButton) { changeStyleKey(nil, sender.tag) }
    @objc private func changeColor(_ sender: NSColorWell) { var style = canvas.currentStyle; style.color = AnnotationColor(sender.color); canvas.changeStyle(style) }
    private func changeStyleKey(_ delta: CGFloat?, _ color: Int?) {
        guard canvas.currentTool != .select else { return }
        var style = canvas.currentStyle
        if let delta { if canvas.currentTool == .text { style.fontSize = min(200,max(8,style.fontSize+delta)) } else if canvas.currentTool == .mask { style.maskStrength = min(80,max(4,style.maskStrength+delta)) } else { style.width = min(80, max(1, style.width + delta)) } }
        if let color, canvas.currentTool != .mask { style.color = AnnotationColor.palette[color] }
        canvas.changeStyle(style)
    }
    @objc private func finishText() { _ = canvas.finishTextEditing() }
    @objc private func cancelText() { canvas.cancelTextEditing() }
    @objc private func changeTextStyle() {
        var style = canvas.currentStyle; style.bold = boldButton.state == .on; style.textBackground = textBackground.state == .on; style.backgroundColor = AnnotationColor(backgroundWell.color); canvas.changeStyle(style)
    }
    @objc private func changeMask() {
        var style = canvas.currentStyle; style.maskEffect = maskPicker.selectedSegment == 0 ? .pixelate : .blur; if canvas.selected == nil { style.maskBrush = maskMode.selectedSegment == 1 }; canvas.changeStyle(style)
    }
    @objc private func changeBrush(_ sender: NSSlider) { var style = canvas.currentStyle; style.width = CGFloat(sender.doubleValue.rounded()); canvas.changeStyle(style) }
    @objc private func changeOptions() {
        var style = canvas.currentStyle; style.filled = fillButton.selectedSegment > 0; style.fillOpacity = fillButton.selectedSegment == 1 ? 0.25 : 1; style.dashed = dashButton.state == .on
        if arrowPicker.selectedSegment >= 0 { style.arrowHead = ArrowHead.allCases[arrowPicker.selectedSegment] }
        canvas.changeStyle(style)
    }
    @objc private func changeCorner(_ sender: NSSlider) { var style = canvas.currentStyle; style.cornerRadius = CGFloat(sender.doubleValue.rounded()); canvas.changeStyle(style) }
    @objc private func changeNumber() {
        guard let value = Int(numberField.stringValue), (1...999999).contains(value), !canvas.hasDraft else {
            numberField.stringValue = "\(canvas.selected?.number ?? annotationDocument.state.nextNumber)"
            status.stringValue = "编号须为 1–999999 的整数"; return
        }
        var state = annotationDocument.state
        if let id = canvas.selectedID, let index = state.objects.firstIndex(where: { $0.id == id }) { state.objects[index].number = value }
        else { state.nextNumber = value }
        annotationDocument.commit(state); updateControls()
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if notification.object as? NSTextField === numberField { changeNumber() }
    }
    @objc private func toggleEditing() {
        guard pinned else { return }
        guard canvas.finishTextEditing() else { return }
        window?.makeFirstResponder(canvas); canvas.cancelGesture(); canvas.chooseTool(.select); styleExpanded = false
        if !editing, let window {
            viewingFrame = window.frame; window.minSize = CGSize(width:880,height:300)
            var frame = window.frame; frame.size.width = max(880,frame.width); frame.size.height = max(360,frame.height); setVisibleFrame(frame)
        } else if let window {
            window.minSize = CGSize(width:420,height:260)
            if let viewingFrame { setVisibleFrame(CGRect(x:window.frame.minX,y:window.frame.maxY-viewingFrame.height,width:viewingFrame.width,height:viewingFrame.height)) }
            viewingFrame = nil
        }
        editing.toggle(); updateControls()
    }
    private func setVisibleFrame(_ proposed: CGRect) {
        guard let window else { return }
        var frame = proposed
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.width,visible.width); frame.size.height = min(frame.height,visible.height)
            frame.origin.x = max(visible.minX,min(frame.minX,visible.maxX-frame.width)); frame.origin.y = max(visible.minY,min(frame.minY,visible.maxY-frame.height))
        }
        window.setFrame(frame,display:true)
    }
    private func zoom(_ factor: CGFloat) {
        guard pinned, let window, let screen = window.screen else { return }
        let previous = window.frame
        let width = min(screen.visibleFrame.width, max(window.minSize.width, previous.width * factor))
        let height = min(screen.visibleFrame.height, max(window.minSize.height, previous.height * factor))
        setVisibleFrame(CGRect(x:previous.midX-width/2,y:previous.midY-height/2,width:width,height:height))
    }
    private func invalidateRecognition() {
        generation += 1; recognition?.cancel(); recognition = nil; overlay.resetSelection(); overlay.analysis = nil
        status.stringValue = canvas.hasDraft || annotationDocument.inTransaction ? "正在编辑…" : "正在识别文字…"
        updateControls()
    }
    private func recognize() {
        invalidateRecognition()
        guard !closed, !canvas.hasDraft, !annotationDocument.inTransaction, let image = canvas.previewImage else { return }
        let revision = annotationDocument.revision, token = generation
        let occlusions = annotationDocument.state.occlusions
        let textOverlays = annotationDocument.state.safeTextOverlays
        if !occlusions.isEmpty && baseRegionsTask == nil {
            let base = annotationDocument.baseImage
            baseRegionsTask = Task.detached(priority: .userInitiated) { try SafeTextImage.textRegions(in: base) }
        }
        let sourceGeometry = baseRegionsTask
        recognition = Task { @MainActor [weak self] in
            do {
                var config = ImageAnalyzer.Configuration(.text); config.locales = ["zh-Hans", "zh-Hant", "en-US"]
                var input = image
                if !occlusions.isEmpty {
                    guard let sourceGeometry else { throw SafeTextImage.PreparationError.unavailableGeometry }
                    let regions = try await sourceGeometry.value
                    try Task.checkCancellation()
                    let preparation = Task.detached(priority: .userInitiated) { try SafeTextImage.prepare(image: image, baseRegions: regions, occlusions: occlusions) }
                    input = try await withTaskCancellationHandler(operation: { try await preparation.value }, onCancel: { preparation.cancel() })
                    if !textOverlays.isEmpty {
                        guard let restored = AnnotationRenderer.render(base:input,objects:textOverlays) else { throw SafeTextImage.PreparationError.allocation }
                        input = restored
                    }
                }
                try Task.checkCancellation()
                let result = try await ImageAnalyzer().analyze(input, orientation: .up, configuration: config)
                guard let self, !Task.isCancelled, !closed, token == generation, revision == annotationDocument.revision else { return }
                overlay.analysis = result; overlay.setContentsRectNeedsUpdate(); updateCopyTitle()
                status.stringValue = result.transcript.isEmpty ? "没有发现文字" : "拖选文字后 ⌘C 复制 · \(image.width) × \(image.height) px"
            } catch {
                guard let self, !closed, !Task.isCancelled, token == generation else { return }
                if !occlusions.isEmpty { baseRegionsTask = nil }
                status.stringValue = occlusions.isEmpty ? "文字识别失败，仍可复制或保存图片" : "安全文字暂不可用，仍可复制或保存处理后的图片"
            }
        }
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldBeginAt point: CGPoint, forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool { canvas.canSelectText(at: canvas.convert(point, from: overlayView)) }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldHandleKeyDownEvent event: NSEvent) -> Bool {
        if event.keyCode == 53 && overlay.hasActiveTextSelection { overlay.resetSelection(); return false }
        return !canvas.handleKey(event)
    }
    var recognitionForVerification: Task<Void, Never>? { recognition }
    var recognizedTextForVerification: String { overlay.text }
    var selectedTextForVerification: String { overlay.selectedText }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu { makeContextMenu() }
    func stableImage() -> CGImage? {
        guard !canvas.hasDraft, !annotationDocument.inTransaction else { status.stringValue = "请先完成当前编辑"; return nil }
        guard let image = canvas.previewImage else { status.stringValue = "图片合成失败，请撤销后重试"; return nil }
        return image
    }
    @objc func copy(_ sender: Any?) {
        let selected = overlay.selectedText
        if !overlay.isHidden && !selected.isEmpty { writeText(selected) } else { copyImage() }
    }
    override func selectAll(_ sender: Any?) {
        guard !overlay.isHidden else { return }
        let text = overlay.text; guard !text.isEmpty else { return }; overlay.selectedRanges = [text.startIndex..<text.endIndex]; updateCopyTitle()
    }
    @objc func undo(_ sender: Any?) { if let input = canvas.textEditor { guard !input.hasMarkedText() else { return }; input.breakUndoCoalescing(); input.undoManager?.undo(); updateControls() } else { guard !canvas.hasDraft else { return }; annotationDocument.undo() } }
    @objc func redo(_ sender: Any?) { if let input = canvas.textEditor { guard !input.hasMarkedText() else { return }; input.undoManager?.redo(); updateControls() } else { guard !canvas.hasDraft else { return }; annotationDocument.redo() } }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copySelectedText) { return !canvas.hasDraft && !overlay.isHidden && !overlay.selectedText.isEmpty }
        if menuItem.action == #selector(copyAllText) { return !canvas.hasDraft && !annotationDocument.inTransaction && !overlay.text.isEmpty }
        if let action = menuItem.action, [#selector(copyImage),#selector(saveImage),#selector(saveDocument(_:)),#selector(pinImage)].contains(action) { return !closed && !canvas.hasDraft && !annotationDocument.inTransaction && canvas.previewImage != nil }
        if menuItem.action == #selector(opacityPreset(_:)) { menuItem.state = Int(((window?.alphaValue ?? 1)*100).rounded()) == menuItem.tag ? .on : .off; return pinned }
        if menuItem.action == #selector(undo(_:)) { return annotationDocument.canUndo && !canvas.hasDraft && !annotationDocument.inTransaction }
        if menuItem.action == #selector(redo(_:)) { return annotationDocument.canRedo && !canvas.hasDraft && !annotationDocument.inTransaction }
        return true
    }
    @objc func copyImage() {
        guard let image = stableImage() else { return }
        guard let png = Self.encoded(image, type: .png) else { status.stringValue = "图片编码失败"; return }
        let pasteboard = NSPasteboard.general; pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { status.stringValue = "复制失败，请重试"; return }
        status.stringValue = "图片已复制"; if !pinned { close() }
    }
    @objc private func copySelectedText() {
        guard !canvas.hasDraft, !annotationDocument.inTransaction, !overlay.isHidden, !overlay.selectedText.isEmpty else { status.stringValue = "请先选择文字"; return }; writeText(overlay.selectedText)
    }
    @objc func copyAllText() {
        guard !canvas.hasDraft, !annotationDocument.inTransaction, !overlay.text.isEmpty else { status.stringValue = "当前没有可复制文字"; return }
        writeText(overlay.text)
    }
    private func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general; pasteboard.clearContents()
        status.stringValue = pasteboard.setString(text, forType: .string) ? "文字已复制" : "复制失败，请重试"
    }
    @objc func saveDocument(_ sender: Any?) { saveImage() }
    @objc func saveImage() {
        guard stableImage() != nil, let window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.directoryURL = preferences.usableSaveDirectory
        panel.nameFieldStringValue = "CcShot-\(Int(Date().timeIntervalSince1970)).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, !self.closed, let url = panel.url, let image = self.stableImage() else { return }
            let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
            guard let data = Self.encoded(image, type: type) else { self.status.stringValue = "图片编码失败"; return }
            do { try data.write(to: url, options: .atomic); self.status.stringValue = "图片已保存" }
            catch { self.status.stringValue = "保存失败，请检查目录权限与可用空间" }
        }
    }
    static func encoded(_ image: CGImage, type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
    @objc func pinImage() { guard stableImage() != nil else { return }; onPin?(annotationDocument.copied()) }
    @objc private func changeOpacity(_ sender: NSSlider) { window?.alphaValue = sender.doubleValue }
    override func cancelOperation(_ sender: Any?) {
        if overlay.hasActiveTextSelection { overlay.resetSelection() }
        else if canvas.hasDraft { canvas.cancelGesture() }
        else if canvas.tool != .select { canvas.chooseTool(.select) }
        else if canvas.selected != nil { canvas.deselect() }
        else if pinned && editing { toggleEditing() }
        else { close() }
    }
    func windowWillClose(_ notification: Notification) {
        closed = true; generation += 1; recognition?.cancel(); recognition = nil; baseRegionsTask?.cancel(); baseRegionsTask = nil; overlay.analysis = nil; annotationDocument.onChange = nil; onClose?()
    }
}

extension ImageWindow {
    func coreLayoutChecks() -> [String:Bool] {
        guard let window, let root = window.contentView, !pinned else { return [:] }
        let original = window.frame
        let previousCopyTitle = copyButton.title; copyButton.title = "复制文字"
        window.setFrame(CGRect(x:original.minX,y:original.minY,width:880,height:360),display:true); root.layoutSubtreeIfNeeded()
        let controls = toolRow.arrangedSubviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
        let contained = controls.allSatisfy { value in
            let rect = value.alignmentRect(forFrame:value.frame)
            return root.bounds.contains(root.convert(value.bounds,from:value)) && rect.minX >= -0.5 && rect.maxX <= toolRow.bounds.maxX+0.5 && rect.minY >= -0.5 && rect.maxY <= toolRow.bounds.maxY+0.5 && value.frame.width >= value.intrinsicContentSize.width-1
        }
        var result = ["core_tools_share_first_row":toolButtons.count == 8 && toolButtons.values.allSatisfy { $0.superview === toolRow && !$0.isHidden },"minimum_window_keeps_primary_controls":contained,"minimum_window_keeps_canvas":canvas.bounds.height >= 160]
        canvas.chooseTool(.rectangle); toggleStyle(); root.layoutSubtreeIfNeeded()
        result["style_panel_stays_in_window"] = !styleRow.isHidden && root.bounds.contains(root.convert(styleRow.bounds,from:styleRow)) && root.bounds.contains(root.convert(optionRow.bounds,from:optionRow))
        toggleStyle(); canvas.chooseTool(.select); copyButton.title = previousCopyTitle
        window.setFrame(original,display:true); root.layoutSubtreeIfNeeded()
        return result
    }
}
