import AppKit
import CoreImage
import VisionKit
import UniformTypeIdentifiers

@MainActor final class AnnotationWindow: NSWindow {
    override var canBecomeKey: Bool {true}
    var handleCanvasKey: ((NSEvent) -> Bool)?
    var copiesScreenshotOnReturn = false
    var copyScreenshotSelection: (() -> Void)?
    private var acceptsScreenshotReturn: Bool { attachedSheet == nil && !(firstResponder is NSTextView) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if acceptsScreenshotReturn,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c", let copyScreenshotSelection {
            copyScreenshotSelection()
            return true
        }
        if copiesScreenshotOnReturn, event.isScreenshotReturn, acceptsScreenshotReturn, handleCanvasKey?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.isScreenshotReturn && !acceptsScreenshotReturn {
            super.keyDown(with: event)
            return
        }
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
    private let status = ScreenshotStatus(labelWithString: "正在识别文字…")
    private let screenshot:ScreenshotPresentation?
    private var screenshotView:ScreenshotView?
    private var toolbarPanel:CoreSurfaceView?
    private var parametersPanel:CoreSurfaceView?
    private var toolbarContent:FloatingControls?
    private var parametersContent:FloatingControls?
    var onReselect:((CGRect)->Bool)?
    var isScreenshot:Bool {screenshot != nil}
    private let toolRow = NSStackView()
    private let viewerRow = NSStackView()
    private var copyButton: NSButton!
    private var pinButton: NSButton!
    private var saveButton: NSButton!
    private var donePinButton: NSButton!
    private var pinChrome:PinChrome?
    private var floatingEditor:Bool {screenshot != nil || pinned}
    private let styleRow = NSStackView()
    private let optionRow = NSStackView()
    private let markupRow = NSStackView()
    private var markupSwatches: [ToolbarButton] = []
    private var arrowSamples: [ToolbarButton] = []
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private let widthSlider = StyleSlider(value: 4, minValue: 1, maxValue: 80, target: nil, action: nil)
    private let widthTitle = NSTextField(labelWithString: "粗细")
    private var presetButtons: [NSButton] = []
    private var colorControls: [NSView] = []
    private let maskPicker = NSSegmentedControl(labels: ["实心", "马赛克", "模糊"], trackingMode: .selectOne, target: nil, action: nil)
    private let maskMode = NSSegmentedControl(labels: ["框选", "涂抹"], trackingMode: .selectOne, target: nil, action: nil)
    private let brushWidth = StyleSlider(value: 32, minValue: 1, maxValue: 80, target: nil, action: nil)
    private let brushLabel = NSTextField(labelWithString: "笔宽")
    private let widthLabel = NSTextField(labelWithString: "4 px")
    private let strokeWidthField = NSTextField(string: "4")
    private let colorWell = ScreenshotColorWell()
    private let fillButton = NSSegmentedControl(labels: ["描边", "半透明", "实心"], trackingMode: .selectOne, target: nil, action: nil)
    private let dashButton = NSSegmentedControl(labels: ["实线", "虚线"], trackingMode: .selectOne, target: nil, action: nil)
    private let lineTitle = NSTextField(labelWithString: "线型")
    private let fillTitle = NSTextField(labelWithString: "填充")
    private let cornerSlider = StyleSlider(value: 0, minValue: 0, maxValue: 80, target: nil, action: nil)
    private let cornerLabel = NSTextField(labelWithString: "圆角")
    private let arrowPicker = NSSegmentedControl(labels: ["实心", "开口", "双头"], trackingMode: .selectOne, target: nil, action: nil)
    private let arrowTitle = NSTextField(labelWithString: "箭头样式")
    private let numberLabel = NSTextField(labelWithString: "下一号")
    private let numberField = NSTextField(string: "1")
    private let boldButton = NSButton(title: "B", target: nil, action: nil)
    private let textBackground = NSButton(title: "底色", target: nil, action: nil)
    private let fontSizeField = NSTextField(string: "24")
    private let paletteTray = NSStackView()
    private var finishTextButton: NSButton!
    private var cancelTextButton: NSButton!
    private let editButton = ToolbarButton(title: "编辑", target: nil, action: nil)
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var editing: Bool
    private var baseRegionsTask: Task<[CGRect], Error>?
    private var recognition: Task<Void, Never>?
    private var generation = 0
    private var closed = false
    private let preferences: AppPreferences
    private let pasteboard: NSPasteboard
    var onClose: (() -> Void)?
    var onPin: ((AnnotationDocument) -> Void)?

    convenience init(image: CGImage, pinned: Bool, preferences: AppPreferences = .shared) {
        self.init(annotationDocument: AnnotationDocument(image: image), pinned: pinned, preferences: preferences)
    }
    init(annotationDocument: AnnotationDocument, pinned: Bool, preferences: AppPreferences = .shared, screenshot:ScreenshotPresentation? = nil,pinFrame:CGRect?=nil, pasteboard: NSPasteboard = .general) {
        self.annotationDocument = annotationDocument; self.pinned = pinned; self.preferences = preferences; self.screenshot = pinned ? nil : screenshot
        self.pasteboard = pasteboard
        canvas = AnnotationCanvas(document: annotationDocument, preferences: preferences, compactStyles: screenshot != nil || pinned)
        editing = !pinned
        let ratio = CGFloat(annotationDocument.baseImage.height) / CGFloat(annotationDocument.baseImage.width)
        let width: CGFloat = min(pinned ? 900 : 1040, max(pinned ? 420 : 880, CGFloat(annotationDocument.baseImage.width)))
        let height = min(780, max(pinned ? 260 : 360, width * ratio + 100))
        let pinScreen=pinFrame.flatMap {frame in NSScreen.screens.first {$0.frame.contains(CGPoint(x:frame.midX,y:frame.midY))}} ?? NSScreen.main
        let pinRect=PinLayout.frame(pixels:CGSize(width:annotationDocument.baseImage.width,height:annotationDocument.baseImage.height),scale:pinScreen?.backingScaleFactor ?? 2,visible:pinScreen?.visibleFrame ?? CGRect(x:0,y:0,width:1200,height:800),preferred:pinFrame)
        let rect=pinned ? pinRect : screenshot?.screenFrame ?? NSRect(x:0,y:0,width:width,height:height)
        let window = AnnotationWindow(contentRect:rect,styleMask:pinned ? [.borderless,.resizable] : screenshot == nil ? [.titled,.closable,.resizable,.miniaturizable] : [.borderless],backing:.buffered,defer:false)
        window.copiesScreenshotOnReturn = screenshot != nil
        window.title = pinned ? "ccShot · 钉图" : "ccShot"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: pinned ? 420 : 880, height: pinned ? 260 : 300)
        window.backgroundColor = CoreAppearance.surface
        if screenshot != nil {window.level = .screenSaver;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]}
        if pinned { window.minSize=ratio>1 ? CGSize(width:32/ratio,height:32) : CGSize(width:32,height:32*ratio);window.contentAspectRatio=CGSize(width:annotationDocument.baseImage.width,height:annotationDocument.baseImage.height);window.backgroundColor = .clear;window.isOpaque=false;window.hasShadow=true;window.acceptsMouseMovedEvents=true;window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        super.init(window: window)
        window.delegate = self
        let root:NSView
        if let screenshot {
            let view=ScreenshotView(presentation:screenshot,imagePixels:CGSize(width:annotationDocument.baseImage.width,height:annotationDocument.baseImage.height));screenshotView=view;root=view
        } else if pinned {root=PinSurface()} else {root=CoreSurfaceView()}
        window.contentView = root
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        canvas.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        overlay.delegate = self; overlay.trackingImageView = canvas
        overlay.preferredInteractionTypes = .textSelection
        // 只增强系统选字层的可见度，保留原生选区和截图像素。
        if let contrast = CIFilter(name: "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 2.6)]) {
            overlay.contentFilters = [contrast]
        }
        overlay.autoresizingMask = [.width, .height]; canvas.addSubview(overlay)
        buildStyles()
        undoButton = iconButton("arrow.uturn.backward", "撤销（⌘Z）", #selector(undo(_:)))
        redoButton = iconButton("arrow.uturn.forward", "重做（⌘⇧Z）", #selector(redo(_:)))
        toolRow.addArrangedSubview(undoButton); toolRow.addArrangedSubview(redoButton)
        toolRow.setCustomSpacing(12,after:redoButton)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant:8).isActive = true
        pinButton = button("钉住",#selector(pinImage)); saveButton = button("保存",#selector(saveImage)); copyButton = button("复制",floatingEditor ? #selector(toolbarCopy) : #selector(copy(_:)))
        donePinButton = button("完成",#selector(toggleEditing))
        for value in [donePinButton,pinButton,saveButton,copyButton] { toolRow.addArrangedSubview(value!) }
        finishTextButton = button("完成文字",#selector(finishText)); cancelTextButton = button("取消",#selector(cancelText))
        finishTextButton.toolTip = "完成文字（⌘Return）"; cancelTextButton.toolTip = "取消文字（Esc）"
        toolRow.addArrangedSubview(finishTextButton); toolRow.addArrangedSubview(cancelTextButton)
        // 弹性空白放到整组操作之后，避免把钉住与常用标注推得过远。
        toolRow.addArrangedSubview(spacer)
        editButton.target = self; editButton.action = #selector(toggleEditing); editButton.bezelStyle = .rounded; editButton.font = .systemFont(ofSize:14)
        (copyButton as? ToolbarButton)?.minimumTitle = "复制文字"
        viewerRow.spacing = 8
        for (view,symbol) in [(editButton,"pencil"),(button("保存", #selector(saveImage)),"square.and.arrow.down"),(button("关闭",#selector(closeImage)),"xmark")] {view.image=NSImage(systemSymbolName:symbol,accessibilityDescription:view.title);(view as? ToolbarButton)?.configureToolbarStyle();viewerRow.addArrangedSubview(view)}
        canvas.menu = makeContextMenu()
        status.textColor = .labelColor; status.font = .systemFont(ofSize:13)
        if screenshot != nil {configureScreenshot(root:root)} else if pinned {configurePin(root:root)} else {
        let stack = NSStackView(views:[toolRow,viewerRow,styleRow,optionRow,canvas,status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            toolRow.widthAnchor.constraint(equalTo:stack.widthAnchor), canvas.widthAnchor.constraint(equalTo: stack.widthAnchor), canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        }
        canvas.onError = { [weak self] message in self?.status.stringValue = message }
        canvas.onPreviewBegin = { [weak self] in self?.invalidateRecognition() }
        canvas.onDocumentChanged = { [weak self] in self?.updateControls(); self?.recognize() }
        canvas.onSelectionChanged = { [weak self] in self?.updateControls() }
        canvas.onStyleKey = { [weak self] delta, color in self?.changeStyleKey(delta, color) }
        canvas.onConfirm = { [weak self] in self?.completeScreenshot() }
        canvas.onSpace = { [weak self] in if self?.pinned == true { self?.toggleEditing() } else { self?.completeScreenshot() } }
        if screenshot != nil {
            window.copyScreenshotSelection = { [weak self] in self?.copy(nil) }
        }
        canvas.onExit = { [weak self] in self?.cancelOperation(nil) }
        canvas.onZoom = { [weak self] factor in self?.zoom(factor) }
        screenshotView?.onLayout = { [weak self] in self?.layoutScreenshot() }
        screenshotView?.onAdjustmentBegin = { [weak self] in self?.invalidateRecognition() }
        screenshotView?.onAdjustmentCancel = { [weak self] in self?.recognize() }
        screenshotView?.onRegionChange = { [weak self] rect in self?.onReselect?(rect) ?? false }
        status.onChange = { [weak self] in if self?.screenshot != nil {self?.layoutScreenshot()} else if self?.pinned == true {self?.layoutPin()} }
        updateControls(); if screenshot == nil && !pinned {window.center()} else if let screenshot {window.setFrame(screenshot.screenFrame,display:false)}
        showWindow(nil); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.handleCanvasKey = { [weak self] event in guard self?.screenshotView?.isAdjusting != true else {return false}; return self?.canvas.handleKey(event) ?? false }
        window.makeFirstResponder(canvas)
        root.layoutSubtreeIfNeeded(); overlay.frame = canvas.bounds; overlay.setContentsRectNeedsUpdate()
        recognize()
    }
    required init?(coder: NSCoder) { nil }
    private func configureScreenshot(root:NSView) {
        guard let root=root as? ScreenshotView else {return}
        root.addSubview(canvas);root.imageView=canvas;root.installBorder()
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        func panel(_ rows:[NSView], primary: Bool = false)->(CoreSurfaceView,FloatingControls) {
            let panel=CoreSurfaceView();panel.wantsLayer=true;panel.layer?.cornerRadius=20;panel.layer?.masksToBounds=true
            panel.layer?.borderWidth=1;panel.layer?.borderColor=NSColor.separatorColor.cgColor
            let content = FloatingControls(rows: rows, primaryToolbar: primary)
            panel.addSubview(content)
            root.addSubview(panel);return(panel,content)
        }
        configureFloatingTools()
        (toolbarPanel,toolbarContent)=panel([toolRow], primary: true)
        (parametersPanel,parametersContent)=panel([markupRow])
        viewerRow.isHidden=true
        root.addSubview(status);root.chrome=[toolbarPanel!,parametersPanel!,status]
        buildMarkupOptions()
    }
    private func configureFloatingTools() {
        for view in toolRow.arrangedSubviews {toolRow.removeArrangedSubview(view);view.removeFromSuperview()}
        let symbols:[AnnotationTool:String]=[.arrow:"arrow.up.right",.rectangle:"rectangle",.text:"textformat",.pen:"pencil",.mask:"rectangle.fill",.highlight:"highlighter",.number:"number.circle",.select:"cursorarrow"]
        for tool in [AnnotationTool.select,.arrow,.rectangle,.text,.pen,.mask,.highlight,.number] {
            guard let button=toolButtons[tool] else {continue}
            button.title = ""
            button.setAccessibilityLabel(tool == .select ? "选择文字或对象" : tool == .rectangle ? "画框" : tool.title)
            if tool == .text {
                let icon=NSImage(size:NSSize(width:16,height:20),flipped:false) {_ in
                    ("T" as NSString).draw(at:CGPoint(x:2,y:0),withAttributes:[.font:NSFont.systemFont(ofSize:19,weight:.medium),.foregroundColor:NSColor.black]);return true
                };icon.isTemplate=true;button.image=icon
            } else {button.image=NSImage(systemSymbolName:symbols[tool]!,accessibilityDescription:tool.title)}
            toolRow.addArrangedSubview(button)
        }
        func separator() {let line=NSBox();line.boxType = .separator;line.widthAnchor.constraint(equalToConstant:1).isActive=true;line.heightAnchor.constraint(equalToConstant:24).isActive=true;toolRow.addArrangedSubview(line);toolRow.setCustomSpacing(8,after:line)}
        separator()
        toolRow.addArrangedSubview(undoButton);toolRow.addArrangedSubview(redoButton);separator()
        for (button, symbol) in [(pinButton!, "pin"), (saveButton!, "square.and.arrow.down")] {
            button.setAccessibilityLabel(button.title)
            button.toolTip = button.title
            button.title = ""
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            toolRow.addArrangedSubview(button)
        }
        if pinned {
            donePinButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "完成标注")
            toolRow.addArrangedSubview(donePinButton)
        } else {
            copyButton.title = "完成"
            copyButton.action = #selector(completeScreenshot)
            copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            (copyButton as? ToolbarButton)?.minimumTitle = ""
            (copyButton as? ToolbarButton)?.primary = true
            toolRow.addArrangedSubview(copyButton)
        }
        toolRow.addArrangedSubview(iconButton("xmark", "关闭（Esc）", #selector(closeImage)))
        toolRow.spacing = 4
        for button in toolRow.arrangedSubviews.compactMap({ $0 as? ToolbarButton }) {
            button.configureToolbarStyle()
        }
    }
    private func buildMarkupOptions() {
        markupRow.spacing = 5
        for (index, title) in ["珊瑚橙", "琥珀黄", "晴空蓝"].enumerated() {
            let color = AnnotationColor.markupPalette[index]
            let button = ToolbarButton(title: "", target: self, action: #selector(markupColor(_:)))
            button.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                color.nsColor.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            button.tag = index
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.setButtonType(.pushOnPushOff)
            button.configureToolbarStyle()
            markupRow.addArrangedSubview(button)
            markupSwatches.append(button)
        }
        for (index, title) in ["直线箭头", "曲线箭头"].enumerated() {
            let curved = index == 1
            let button = ToolbarButton(title: "", target: self, action: #selector(markupShape(_:)))
            let sample = NSImage(size: NSSize(width: 32, height: 22), flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                var style = AnnotationStyle.initial(.arrow)
                style.width = 2
                style.curvedArrow = curved
                var arrow = AnnotationObject(tool: .arrow, style: style,
                                             start: CGPoint(x: 3, y: curved ? 5 : 8),
                                             end: CGPoint(x: 28, y: 14))
                arrow.applyPresetCurve()
                return AnnotationRenderer.draw(arrow, in: context)
            }
            sample.isTemplate = true
            button.sample = true
            button.image = sample
            button.tag = index
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.setButtonType(.pushOnPushOff)
            button.configureToolbarStyle()
            markupRow.addArrangedSubview(button)
            arrowSamples.append(button)
        }
    }
    @objc private func markupColor(_ sender: NSButton) {
        canvas.chooseMarkup(color: AnnotationColor.markupPalette[sender.tag])
    }
    @objc private func markupShape(_ sender: NSButton) {
        canvas.chooseMarkup(curved: sender.tag == 1)
    }
    private func updateMarkupOptions() {
        let tool = canvas.currentTool
        markupRow.isHidden = !editing || (tool != .arrow && tool != .rectangle)
        let style = canvas.currentStyle
        for (index, button) in markupSwatches.enumerated() {
            button.state = AnnotationColor.markupPalette[index] == style.color ? .on : .off
            button.isEnabled = !canvas.hasDraft
            button.refreshAppearance()
        }
        let curved = canvas.selected.map { $0.curveControl != nil } ?? (style.curvedArrow == true)
        for (index, button) in arrowSamples.enumerated() {
            button.isHidden = tool != .arrow
            button.state = (index == 1) == curved ? .on : .off
            button.isEnabled = !canvas.hasDraft
            button.refreshAppearance()
        }
    }
    private func configurePin(root:NSView) {
        guard let root=root as? PinSurface,let window else {return}
        configureFloatingTools();buildMarkupOptions()
        root.addSubview(canvas);canvas.autoresizingMask=[.width,.height]
        root.onLayout={ [weak self] in self?.layoutPin() }
        pinChrome=PinChrome(parent:window,root:root,owner:self,primaryRows:[toolRow,viewerRow],secondaryRows:[markupRow,status])
        pinChrome?.isAuxiliaryActive={ [weak self] in self?.colorWell.isActive == true && NSColorPanel.shared.isVisible }
        var dragStart:(mouse:CGPoint,origin:CGPoint)?
        canvas.onBackgroundDrag={ [weak self] event in
            guard let window=self?.window else {return}
            let mouse=window.convertPoint(toScreen:event.locationInWindow)
            if event.type == .leftMouseDown {dragStart=(mouse,window.frame.origin);window.makeKeyAndOrderFront(nil)}
            else if event.type == .leftMouseDragged,let start=dragStart {
                window.setFrameOrigin(CGPoint(x:start.origin.x+mouse.x-start.mouse.x,y:start.origin.y+mouse.y-start.mouse.y))
            } else if event.type == .leftMouseUp {dragStart=nil}
        }
        canvas.canStartTextSelection={ [weak self] point in
            guard let self,!overlay.isHidden else {return false}
            let local=overlay.convert(point,from:canvas)
            // VisionKit 的文字命中查询以图片左上角为原点，AppKit 事件以左下角为原点。
            return overlay.analysisHasText(at:CGPoint(x:local.x,y:overlay.bounds.maxY-local.y))
        }
    }
    private func layoutPin() {
        guard pinned,let root=window?.contentView else {return}
        if canvas.frame != root.bounds {canvas.frame=root.bounds;overlay.frame=canvas.bounds;overlay.setContentsRectNeedsUpdate()}
        status.isHidden = hidesRoutineStatus
        pinChrome?.layout(editing:editing)
    }
    var suggestedPinFrame:CGRect? {
        guard let window else {return nil}
        return window.convertToScreen(canvas.convert(canvas.contentRect,to:nil))
    }
    func windowDidMove(_ notification:Notification) {if pinned {layoutPin()}}
    func windowDidResize(_ notification:Notification) {if pinned {layoutPin()}}
    func windowDidEndLiveResize(_ notification: Notification) { updateControls() }
    func windowDidBecomeKey(_ notification:Notification) {pinChrome?.refreshVisibility()}
    func windowDidResignKey(_ notification:Notification) {pinChrome?.refreshVisibility()}
    private func layoutScreenshot() {
        guard let root=screenshotView,let toolbarPanel,let parametersPanel,let toolbarContent,let parametersContent else {return}
        let maxWidth = max(0, root.bounds.width - 24)
        let primary = toolbarContent.panelSize(maxWidth: maxWidth)
        let parameterSize = markupRow.isHidden ? .zero : parametersContent.panelSize(maxWidth: maxWidth)
        guard let placement=ScreenshotLayout.make(capture:root.presentation.captureSize,region:root.region,viewport:root.bounds.size,toolbar:primary,parameters:parameterSize,allowsOutsideRegion:!root.presentation.allowsAdjustment) else {
            canvas.isHidden=true;toolbarPanel.isHidden=true;parametersPanel.isHidden=true;root.placement=nil;return
        }
        root.placement=placement;canvas.frame=placement.image;overlay.frame=canvas.bounds;overlay.setContentsRectNeedsUpdate()
        // 仅裁切显示层，合成和保存继续使用原始矩形。
        canvas.layer?.cornerRadius = CoreAppearance.captureRadius(canvas.bounds)
        canvas.isHidden=root.isAdjusting;toolbarPanel.isHidden=root.isAdjusting;parametersPanel.isHidden=root.isAdjusting || placement.parameters == nil
        toolbarPanel.frame=placement.toolbar
        toolbarContent.place(in: toolbarPanel.bounds)
        if let frame = placement.parameters {
            parametersPanel.frame = frame
            parametersContent.place(in: parametersPanel.bounds)
        }
        root.canAdjust=root.presentation.allowsAdjustment && root.sourceGeometryAvailable && annotationDocument.state.objects.isEmpty && !canvas.hasDraft
        status.isHidden = root.isAdjusting || hidesRoutineStatus
        status.sizeToFit()
        let chrome = placement.parameters.map { placement.toolbar.union($0) } ?? placement.toolbar
        let aboveChrome = chrome.maxY + 8
        let belowChrome = chrome.minY - status.frame.height - 8
        let fitsAbove = aboveChrome + status.frame.height <= root.bounds.maxY - 8
        let preferAbove = placement.toolbar.minY >= placement.image.maxY || belowChrome < 8
        let statusY = preferAbove && fitsAbove ? aboveChrome : max(8, belowChrome)
        status.frame.origin = CGPoint(x: placement.toolbar.minX + 8, y: statusY)
        root.refreshBorder()
    }
    func suspendScreenshotForSettings() {
        guard screenshot != nil else {return}
        colorWell.suspend();window?.orderOut(nil)
    }
    func preserveScreenshotAfterScreenChange() {
        guard let root=screenshotView,let window else {return}
        colorWell.suspend();root.sourceGeometryAvailable=false
        if let screen=window.screen ?? NSScreen.main {window.setFrame(screen.frame,display:true)}
        layoutScreenshot()
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = floatingEditor ? ToolbarButton(title:title,target:self,action:action) : NSButton(title:title,target:self,action:action); button.bezelStyle = .rounded; button.font = .systemFont(ofSize:14); button.heightAnchor.constraint(greaterThanOrEqualToConstant:28).isActive = true; return button
    }
    private func iconButton(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let value = button("",action); value.image = NSImage(systemSymbolName:symbol,accessibilityDescription:title); value.imagePosition = .imageOnly
        value.toolTip = title; value.setAccessibilityLabel(title); value.widthAnchor.constraint(equalToConstant: floatingEditor ? ToolbarButton.iconButtonWidth : 28).isActive = true; return value
    }
    private func stylePreview(_ kind: String, width: CGFloat = 2) -> NSImage {
        let image = NSImage(size: NSSize(width:44,height:24),flipped:false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor); context.setFillColor(NSColor.black.cgColor)
            let previewWidth = kind == "width" ? min(16,width) : 2
            context.setLineWidth(previewWidth); context.setLineCap(.round); context.setLineJoin(.round)
            if kind.hasPrefix("fill-") {
                let box = CGRect(x:13,y:4,width:18,height:16)
                if kind != "fill-none" { context.setAlpha(kind == "fill-soft" ? 0.3 : 1); context.fill(box); context.setAlpha(1) }
                context.stroke(box); return true
            }
            if kind == "dashed" { context.setLineDash(phase:0,lengths:[4,3]) }
            // 圆端点也占半个线宽，保持预设的外边界在 4…40，最粗档不会削平。
            let startX = kind == "width" ? 4+previewWidth/2 : 6
            let endX = kind == "width" ? 40-previewWidth/2 : 38
            context.move(to:CGPoint(x:startX,y:12)); context.addLine(to:CGPoint(x:endX,y:12)); context.strokePath()
            if kind == "open" {
                context.move(to:CGPoint(x:30,y:18)); context.addLine(to:CGPoint(x:39,y:12)); context.addLine(to:CGPoint(x:30,y:6)); context.strokePath()
            } else if kind == "filled" || kind == "double" {
                context.move(to:CGPoint(x:39,y:12)); context.addLine(to:CGPoint(x:30,y:18)); context.addLine(to:CGPoint(x:30,y:6)); context.closePath(); context.fillPath()
                if kind == "double" { context.move(to:CGPoint(x:5,y:12)); context.addLine(to:CGPoint(x:14,y:18)); context.addLine(to:CGPoint(x:14,y:6)); context.closePath(); context.fillPath() }
            }
            return true
        }
        image.isTemplate = true; return image
    }
    private func configurePreviews(_ control: NSSegmentedControl, labels: [String], kinds: [String], name: String) {
        control.setAccessibilityLabel(name)
        for index in labels.indices {
            control.setLabel("",forSegment:index); control.setImage(stylePreview(kinds[index]),forSegment:index)
            control.setWidth(48,forSegment:index); control.setToolTip(labels[index],forSegment:index)
        }
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
        fontSizeField.target = self; fontSizeField.action = #selector(changeFontSize); fontSizeField.delegate = self
        fontSizeField.alignment = .center; fontSizeField.widthAnchor.constraint(equalToConstant:56).isActive = true
        fontSizeField.setAccessibilityLabel("字号"); fontSizeField.toolTip = "字号：8–200"
        styleRow.addArrangedSubview(fontSizeField)
        styleRow.addArrangedSubview(boldButton); styleRow.addArrangedSubview(textBackground)
        for width in [2, 4, 8, 16] { let value = button("\(width)", #selector(widthPreset(_:))); value.tag = width; presetButtons.append(value); styleRow.addArrangedSubview(value) }
        strokeWidthField.target = self; strokeWidthField.action = #selector(changeStrokeWidth); strokeWidthField.delegate = self
        strokeWidthField.alignment = .center; strokeWidthField.widthAnchor.constraint(equalToConstant:50).isActive = true
        strokeWidthField.toolTip = "线宽：1–80 px"; strokeWidthField.setAccessibilityLabel("线宽（像素）")
        styleRow.addArrangedSubview(strokeWidthField)
        paletteTray.spacing = 4; paletteTray.edgeInsets = NSEdgeInsets(top:4,left:6,bottom:4,right:6)
        paletteTray.wantsLayer = true; paletteTray.layer?.cornerRadius = 8
        paletteTray.layer?.borderWidth = 1; paletteTray.layer?.borderColor = NSColor.separatorColor.cgColor
        styleRow.addArrangedSubview(paletteTray)
        for (index, color) in AnnotationColor.palette.enumerated() {
            let value = NSButton(title: "●", target: self, action: #selector(palette(_:))); value.isBordered = false
            value.attributedTitle = NSAttributedString(string: "●", attributes: [.foregroundColor: color.nsColor, .font: NSFont.systemFont(ofSize: 22)])
            value.tag = index; value.toolTip = "颜色 \(index+1)"; value.setAccessibilityLabel("预设颜色 \(index+1)")
            value.widthAnchor.constraint(equalToConstant:26).isActive = true; value.heightAnchor.constraint(equalToConstant:26).isActive = true
            value.wantsLayer = true; value.layer?.cornerRadius = 13; value.layer?.borderWidth = 0.75; value.layer?.borderColor = NSColor.gray.cgColor; colorControls.append(value); paletteTray.addArrangedSubview(value)
        }
        colorWell.target = self; colorWell.action = #selector(changeColor(_:)); colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true; colorControls.append(colorWell); paletteTray.addArrangedSubview(colorWell)
        fillButton.target = self; fillButton.action = #selector(changeOptions)
        dashButton.target = self; dashButton.action = #selector(changeOptions)
        arrowPicker.target = self; arrowPicker.action = #selector(changeOptions)
        configurePreviews(fillButton,labels:["描边","半透明填充","实心填充"],kinds:["fill-none","fill-soft","fill-solid"],name:"填充方式")
        configurePreviews(dashButton,labels:["实线","虚线"],kinds:["solid","dashed"],name:"线型")
        configurePreviews(arrowPicker,labels:["实心箭头","开口箭头","双头箭头"],kinds:["filled","open","double"],name:"箭头样式")
        cornerSlider.target = self; cornerSlider.action = #selector(changeCorner(_:)); cornerSlider.isContinuous = true
        cornerSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        numberField.delegate = self; numberField.target = self; numberField.action = #selector(changeNumber); numberField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        maskPicker.target = self; maskPicker.action = #selector(changeMask)
        maskMode.target = self; maskMode.action = #selector(changeMask)
        brushWidth.target = self; brushWidth.action = #selector(changeBrush(_:)); brushWidth.isContinuous = true
        brushWidth.widthAnchor.constraint(equalToConstant: 90).isActive = true
        boldButton.target = self; boldButton.action = #selector(changeTextStyle)
        textBackground.target = self; textBackground.action = #selector(changeTextStyle)
        for control in [boldButton,textBackground] { control.setButtonType(.pushOnPushOff); control.bezelStyle = .rounded; control.heightAnchor.constraint(greaterThanOrEqualToConstant:28).isActive = true }
        boldButton.font = .boldSystemFont(ofSize:18); boldButton.widthAnchor.constraint(equalToConstant:36).isActive = true
        boldButton.toolTip = "加粗"; boldButton.setAccessibilityLabel("加粗")
        textBackground.toolTip = "浅黄色底色"; textBackground.setAccessibilityLabel("文字底色")
        arrowPicker.setAccessibilityLabel("箭头样式")
        for view in [fillTitle, fillButton, lineTitle, dashButton, cornerLabel, cornerSlider, arrowTitle, arrowPicker, numberLabel, numberField, maskPicker, maskMode, brushLabel, brushWidth] as [NSView] { optionRow.addArrangedSubview(view) }
        for slider in [widthSlider, cornerSlider, brushWidth] {
            slider.beginTracking = { [weak self] in if self?.canvas.selected != nil { self?.annotationDocument.beginTransaction() } }
            slider.endTracking = { [weak self] in if self?.annotationDocument.inTransaction == true { self?.annotationDocument.endTransaction() } }
        }
    }
    private func updateControls() {
        let tool = canvas.currentTool
        canvas.editingEnabled = editing
        toolRow.isHidden = !editing
        styleRow.isHidden = floatingEditor || !editing || tool == .select
        if floatingEditor { updateMarkupOptions() }
        viewerRow.isHidden = !pinned || editing
        if screenshot == nil && !pinned {window?.minSize = CGSize(width:editing ? 880 : 420,height:styleRow.isHidden ? (editing ? 300 : 260) : 480)}
        if screenshot == nil, !pinned, !styleRow.isHidden, let window, window.frame.height < 480 {
            var frame = window.frame; frame.origin.y -= 480-frame.height; frame.size.height = 480; setVisibleFrame(frame)
        }
        let style = canvas.currentStyle
        for (tool, button) in toolButtons {
            let selected = tool == canvas.tool; button.state = selected ? .on : .off
            button.bezelColor = selected ? CoreAppearance.accent : nil; button.contentTintColor = selected ? .white : .labelColor; (button as? ToolbarButton)?.refreshAppearance()
        }
        let strokeWidth = [.rectangle,.ellipse,.arrow,.line,.pen,.highlight].contains(tool)
        let solidMask = tool == .mask && style.maskEffect == .solid
        for control in [widthTitle,widthSlider,widthLabel] as [NSView] {control.isHidden=solidMask}
        for control in presetButtons {control.isHidden=solidMask || tool == .text}
        widthSlider.isHidden = solidMask || tool == .text || strokeWidth; widthLabel.isHidden = widthSlider.isHidden
        strokeWidthField.isHidden = !strokeWidth
        if strokeWidthField.window?.firstResponder !== strokeWidthField.currentEditor() { strokeWidthField.stringValue = "\(Int(style.width))" }
        fontSizeField.isHidden = tool != .text
        if fontSizeField.window?.firstResponder !== fontSizeField.currentEditor() { fontSizeField.stringValue = "\(Int(style.fontSize))" }
        paletteTray.isHidden = tool == .mask && !solidMask
        let width = tool == .text ? style.fontSize : tool == .mask ? style.maskStrength : style.width
        widthTitle.stringValue = tool == .text ? "字号" : tool == .mask ? "强度" : tool == .number ? "大小" : "粗细"
        widthSlider.minValue = tool == .text ? 8 : tool == .mask ? 4 : 1; widthSlider.maxValue = tool == .text ? 200 : 80
        widthSlider.doubleValue = Double(width); widthLabel.stringValue = "\(Int(width)) px";
        let presetWidths: [CGFloat]
        switch tool {
        case .highlight: presetWidths = [12, 20, 28, 36]
        case .mask: presetWidths = [8, 16, 24, 32]
        case .number: presetWidths = [2, 3, 4, 6]
        default: presetWidths = [2, 4, 6, 10]
        }
        for (index, button) in presetButtons.enumerated() {
            let points = presetWidths[index]
            let value = min(80, max(tool == .mask ? 4 : 1, Int((points * canvas.defaultStyleScale).rounded())))
            button.isHidden = solidMask || tool == .text || strokeWidth && index == 3
            button.title = strokeWidth ? "" : "\(value)"; button.tag = value
            button.image = strokeWidth ? stylePreview("width", width: tool == .highlight ? points / 3 : points) : nil
            button.imagePosition = strokeWidth ? .imageOnly : .noImage
            button.identifier = NSUserInterfaceItemIdentifier("style-width-\(value)")
            button.toolTip = "\(widthTitle.stringValue) \(value) px"; button.setAccessibilityLabel(button.toolTip)
        }
        for control in colorControls { control.isHidden = tool == .mask && !solidMask }
        maskPicker.isHidden = tool != .mask; maskMode.isHidden = tool != .mask || canvas.selected != nil
        maskPicker.selectedSegment = MaskEffect.allCases.firstIndex(of:style.maskEffect) ?? 0; maskMode.selectedSegment = style.maskBrush ? 1 : 0
        brushWidth.isHidden = tool != .mask || !style.maskBrush; brushLabel.isHidden = brushWidth.isHidden; brushWidth.doubleValue = Double(style.width)
         colorWell.color = style.color.nsColor
        finishTextButton.isHidden = canvas.textEditor == nil; cancelTextButton.isHidden = canvas.textEditor == nil
        boldButton.isHidden = tool != .text; textBackground.isHidden = tool != .text
        boldButton.state = style.bold ? .on : .off; textBackground.state = style.textBackground ? .on : .off
        boldButton.bezelColor = style.bold ? CoreAppearance.accent : nil
        boldButton.contentTintColor = style.bold ? .white : .labelColor
        textBackground.bezelColor = style.textBackground ? NSColor(calibratedRed:1,green:0.96,blue:0.72,alpha:1) : nil
        textBackground.contentTintColor = style.textBackground ? .black : .labelColor
        fillButton.selectedSegment = style.filled ? (style.fillOpacity < 1 ? 1 : 2) : 0; dashButton.selectedSegment = style.dashed ? 1 : 0
        cornerSlider.doubleValue = Double(style.cornerRadius)
        arrowPicker.selectedSegment = ArrowHead.allCases.firstIndex(of: style.arrowHead) ?? 0
        fillButton.isHidden = ![.rectangle, .ellipse].contains(tool)
        dashButton.isHidden = ![.rectangle, .ellipse, .arrow, .line].contains(tool) || style.filled && [.rectangle, .ellipse].contains(tool)
        fillTitle.isHidden = fillButton.isHidden; lineTitle.isHidden = dashButton.isHidden
        cornerLabel.isHidden = tool != .rectangle; cornerSlider.isHidden = tool != .rectangle
        arrowPicker.isHidden = tool != .arrow; arrowTitle.isHidden = tool != .arrow
        numberLabel.isHidden = tool != .number; numberField.isHidden = tool != .number
        numberLabel.stringValue = canvas.selected == nil ? "下一号" : "编号"
        if numberField.window?.firstResponder !== numberField.currentEditor() { numberField.stringValue = "\(canvas.selected?.number ?? annotationDocument.state.nextNumber)" }
        optionRow.isHidden = styleRow.isHidden || [.pen,.highlight,.text].contains(tool)
        let input = canvas.textEditor
        pinButton.isHidden = pinned || (input != nil && !floatingEditor); saveButton.isHidden = input != nil && !floatingEditor; copyButton.isHidden = input != nil && !floatingEditor; donePinButton.isHidden = !pinned || input != nil
        if let input {
            undoButton.isEnabled = input.undoManager?.canUndo == true && !input.hasMarkedText()
            redoButton.isEnabled = input.undoManager?.canRedo == true && !input.hasMarkedText()
        } else {
            undoButton.isEnabled = annotationDocument.canUndo && !canvas.hasDraft && !annotationDocument.inTransaction
            redoButton.isEnabled = annotationDocument.canRedo && !canvas.hasDraft && !annotationDocument.inTransaction
        }
        overlay.isHidden = canvas.hasDraft || canvas.tool != .select || canvas.selected != nil
        if status.stringValue.hasPrefix("拖选文字后") || status.stringValue.hasPrefix("没有发现文字") || status.stringValue == imageDimensions { status.stringValue = contextualStatus }
        updateCopyTitle()
        if screenshot != nil {layoutScreenshot()} else if pinned {layoutPin()}
        canvas.needsDisplay = true
    }
    private var hidesRoutineStatus: Bool {
        let message = status.stringValue
        return message == imageDimensions || message == "正在识别文字…" || message == "正在编辑…"
            || message.hasPrefix("拖选文字后") || message.hasPrefix("没有发现文字")
    }
    private var imageDimensions: String { "\(annotationDocument.baseImage.width) × \(annotationDocument.baseImage.height) px" }
    private var contextualStatus: String {
        guard !overlay.isHidden else { return imageDimensions }
        return overlay.text.isEmpty ? "没有发现文字 · \(imageDimensions)" : "拖选文字后 ⌘C 复制 · \(imageDimensions)"
    }
    private func updateCopyTitle() {
        let title = !overlay.isHidden && overlay.hasActiveTextSelection && !overlay.selectedText.isEmpty ? "复制文字" : "复制"
        if !floatingEditor { copyButton?.title = title }
        if screenshot != nil { copyButton?.toolTip = "完成（回车）" }
        canvas.menu = makeContextMenu()
        if screenshot != nil {layoutScreenshot()} else if pinned {layoutPin()}
    }
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        if !overlay.isHidden && !overlay.selectedText.isEmpty { menu.addItem(withTitle:"复制文字",action:#selector(copySelectedText),keyEquivalent:"").target = self }
        if !overlay.isHidden && !overlay.text.isEmpty {
            if floatingEditor {
                menu.addItem(withTitle: "全选文字", action: #selector(selectAll(_:)), keyEquivalent: "").target = self
            } else {
                menu.addItem(withTitle: "复制全部文字", action: #selector(copyAllText), keyEquivalent: "").target = self
            }
        }
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
    @objc private func closeImage() { close() }
    @objc private func opacityPreset(_ sender: NSMenuItem) { window?.alphaValue = Double(sender.tag)/100 }
    @objc private func chooseTool(_ sender: NSButton) { canvas.chooseTool(AnnotationTool.allCases[sender.tag]); if canvas.textEditor == nil { window?.makeFirstResponder(canvas) } }
    @objc private func changeWidth(_ sender: NSSlider) { var style = canvas.currentStyle; if canvas.currentTool == .text { style.fontSize = CGFloat(sender.doubleValue.rounded()) } else if canvas.currentTool == .mask { guard style.maskEffect != .solid else {return}; style.maskStrength = CGFloat(sender.doubleValue.rounded()) } else { style.width = CGFloat(sender.doubleValue.rounded()) }; canvas.changeStyle(style) }
    @objc private func widthPreset(_ sender: NSButton) { var style = canvas.currentStyle; if canvas.currentTool == .text { style.fontSize = CGFloat(sender.tag) } else if canvas.currentTool == .mask { guard style.maskEffect != .solid else {return}; style.maskStrength = max(4,CGFloat(sender.tag)) } else { style.width = CGFloat(sender.tag) }; canvas.changeStyle(style) }
    @objc private func palette(_ sender: NSButton) { changeStyleKey(nil, sender.tag) }
    @objc private func changeColor(_ sender: NSColorWell) { var style = canvas.currentStyle; style.color = AnnotationColor(sender.color); if canvas.currentTool == .mask && style.maskEffect == .solid {style.color.alpha=1}; canvas.changeStyle(style) }
    private func changeStyleKey(_ delta: CGFloat?, _ color: Int?) {
        guard canvas.currentTool != .select else { return }
        if floatingEditor {
            if let color, AnnotationColor.markupPalette.indices.contains(color) {
                canvas.chooseMarkup(color: AnnotationColor.markupPalette[color])
            }
            return
        }
        var style = canvas.currentStyle
        if let delta { if canvas.currentTool == .text { style.fontSize = min(200,max(8,style.fontSize+delta)) } else if canvas.currentTool == .mask { if style.maskEffect == .solid {guard style.maskBrush else {return};style.width=min(80,max(1,style.width+delta))} else {style.maskStrength = min(80,max(4,style.maskStrength+delta))} } else { style.width = min(80, max(1, style.width + delta)) } }
        if let color, canvas.currentTool != .mask || style.maskEffect == .solid { style.color = AnnotationColor.palette[color] }
        canvas.changeStyle(style)
    }
    @objc private func finishText() { _ = canvas.finishTextEditing() }
    @objc private func cancelText() { canvas.cancelTextEditing() }
    @objc private func changeStrokeWidth() {
        guard [.rectangle,.ellipse,.arrow,.line,.pen,.highlight].contains(canvas.currentTool) else { return }
        guard let value = Int(strokeWidthField.stringValue), (1...80).contains(value) else {
            strokeWidthField.stringValue = "\(Int(canvas.currentStyle.width))"; status.stringValue = "线宽须为 1–80 的整数"; return
        }
        let clearsOwnError = status.stringValue == "线宽须为 1–80 的整数"
        var style = canvas.currentStyle; style.width = CGFloat(value); canvas.changeStyle(style)
        if clearsOwnError && status.stringValue == "线宽须为 1–80 的整数" { status.stringValue = contextualStatus }
    }
    @objc private func changeFontSize() {
        guard canvas.currentTool == .text else { return }
        guard let size = Int(fontSizeField.stringValue), (8...200).contains(size) else {
            fontSizeField.stringValue = "\(Int(canvas.currentStyle.fontSize))"
            status.stringValue = "字号须为 8–200 的整数"; return
        }
        let clearsOwnError = status.stringValue == "字号须为 8–200 的整数"
        var style = canvas.currentStyle; style.fontSize = CGFloat(size); canvas.changeStyle(style)
        if clearsOwnError && status.stringValue == "字号须为 8–200 的整数" { status.stringValue = contextualStatus }
    }
    @objc private func changeTextStyle() {
        var style = canvas.currentStyle; style.bold = boldButton.state == .on; style.textBackground = textBackground.state == .on; style.backgroundColor = AnnotationColor(red:1,green:0.96,blue:0.72); canvas.changeStyle(style)
    }
    @objc private func changeMask() {
        guard MaskEffect.allCases.indices.contains(maskPicker.selectedSegment) else {return}
        var style = canvas.currentStyle; style.maskEffect = MaskEffect.allCases[maskPicker.selectedSegment]; if style.maskEffect == .solid {style.color.alpha=1}; if canvas.selected == nil { style.maskBrush = maskMode.selectedSegment == 1 }; canvas.changeStyle(style)
    }
    @objc private func changeBrush(_ sender: NSSlider) { var style = canvas.currentStyle; style.width = CGFloat(sender.doubleValue.rounded()); canvas.changeStyle(style) }
    @objc private func changeOptions() {
        var style = canvas.currentStyle; style.filled = fillButton.selectedSegment > 0; style.fillOpacity = fillButton.selectedSegment == 1 ? 0.25 : 1; style.dashed = dashButton.selectedSegment == 1
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
        if notification.object as? NSTextField === fontSizeField { changeFontSize() }
        if notification.object as? NSTextField === strokeWidthField { changeStrokeWidth() }
    }
    @objc private func toggleEditing() {
        guard pinned else { return }
        guard canvas.finishTextEditing() else { return }
        window?.makeFirstResponder(canvas); canvas.cancelGesture(); canvas.chooseTool(.select)
        editing.toggle(); updateControls()
    }
    private func setVisibleFrame(_ proposed: CGRect) {
        guard let window else { return }
        var frame = proposed
        if pinned,let screen=window.screen {
            frame=PinLayout.frame(pixels:canvas.imageSize,scale:screen.backingScaleFactor,visible:screen.visibleFrame,preferred:proposed)
            window.setFrame(frame,display:true);return
        }
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
                status.stringValue = contextualStatus
            } catch {
                guard let self, !closed, !Task.isCancelled, token == generation else { return }
                if !occlusions.isEmpty { baseRegionsTask = nil }
                status.stringValue = occlusions.isEmpty ? "文字识别失败，仍可复制或保存图片" : "安全文字暂不可用，仍可复制或保存处理后的图片"
            }
        }
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldBeginAt point: CGPoint, forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool { canvas.canSelectText(at: canvas.convert(point, from: overlayView)) }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldHandleKeyDownEvent event: NSEvent) -> Bool {
        // 让原生选字层独自消费Esc；手动清除再向外转发会继续触发关窗。
        if event.keyCode == 53 && overlay.hasActiveTextSelection { return true }
        return !canvas.handleKey(event)
    }
    var recognitionForVerification: Task<Void, Never>? { recognition }
    var recognizedTextForVerification: String { overlay.text }
    var selectedTextForVerification: String { overlay.selectedText }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu, for event: NSEvent, at point: CGPoint) -> NSMenu { makeContextMenu() }
    func stableImage() -> CGImage? {
        guard !closed, screenshotView?.isAdjusting != true, !canvas.hasDraft, !annotationDocument.inTransaction else { status.stringValue = "请先完成当前编辑"; return nil }
        guard let image = canvas.previewImage else { status.stringValue = "图片合成失败，请撤销后重试"; return nil }
        return image
    }
    @objc func copy(_ sender: Any?) {
        let selected = overlay.selectedText
        if !overlay.isHidden && !selected.isEmpty { writeText(selected) }
        else { writeImageToClipboard(closeAfter: screenshot == nil) }
    }
    @objc private func completeScreenshot() {
        guard prepareOutput() else { return }
        if screenshot != nil, !overlay.isHidden, !overlay.selectedText.isEmpty {
            if writeText(overlay.selectedText) { close() }
        } else {
            copyImage()
        }
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
    private func prepareOutput()->Bool {
        if floatingEditor,canvas.textEditor != nil {return canvas.finishTextEditing()}
        return true
    }
    @objc private func toolbarCopy() {
        guard prepareOutput() else {return}
        copy(nil)
    }
    @objc func copyImage() { writeImageToClipboard(closeAfter: true) }
    private func writeImageToClipboard(closeAfter: Bool) {
        guard prepareOutput() else {return}
        guard let image = stableImage() else { return }
        guard let png = Self.encoded(image, type: .png) else { status.stringValue = "图片编码失败"; return }
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { status.stringValue = "复制失败，请重试"; return }
        status.stringValue = "图片已复制"; if closeAfter && !pinned { close() }
    }
    @objc private func copySelectedText() {
        guard !canvas.hasDraft, !annotationDocument.inTransaction, !overlay.isHidden, !overlay.selectedText.isEmpty else { status.stringValue = "请先选择文字"; return }; writeText(overlay.selectedText)
    }
    @objc func copyAllText() {
        guard !canvas.hasDraft, !annotationDocument.inTransaction, !overlay.text.isEmpty else { status.stringValue = "当前没有可复制文字"; return }
        writeText(overlay.text)
    }
    @discardableResult private func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        status.stringValue = copied ? "文字已复制" : "复制失败，请重试"
        return copied
    }
    @objc func saveDocument(_ sender: Any?) { saveImage() }
    @objc func saveImage() {
        guard prepareOutput() else {return}
        guard stableImage() != nil, let window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel(); panel.prompt = "保存"; panel.nameFieldLabel = "文件名："; panel.directoryURL = preferences.usableSaveDirectory ?? AppPreferences.defaultSaveDirectory
        panel.nameFieldStringValue = "ccShot-\(Int(Date().timeIntervalSince1970)).png"
        let format = SaveFormatAccessory(panel:panel); panel.accessoryView = format
        panel.isExtensionHidden = false; panel.allowsOtherFileTypes = false; panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, !self.closed, let url = panel.url, let image = self.stableImage() else { return }
            let type = format.type
            guard let data = Self.encoded(image, type: type) else { self.status.stringValue = "图片编码失败"; return }
            do { try data.write(to: url, options: .atomic); self.status.stringValue = "图片已保存" }
            catch { self.status.stringValue = "保存失败，请检查目录权限与可用空间" }
        }
    }
    static func encoded(_ image: CGImage, type: UTType) -> Data? {
        ImageEncoding.data(image,type:type)
    }
    @objc func pinImage() { guard prepareOutput(),stableImage() != nil else { return }; onPin?(annotationDocument.copied());if screenshot != nil {close()} }
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
        colorWell.suspend();pinChrome?.close();pinChrome=nil
        closed = true; generation += 1; recognition?.cancel(); recognition = nil; baseRegionsTask?.cancel(); baseRegionsTask = nil; overlay.analysis = nil; annotationDocument.onChange = nil; onClose?()
    }
}

extension ImageWindow {
    func pinLayoutChecks() async -> [String:Bool] {
        guard pinned,let window,let root=window.contentView,let pinChrome else {return [:]}
        root.layoutSubtreeIfNeeded();layoutPin()
        let original=window.frame
        var checks=["borderless_pin":!window.styleMask.contains(.titled),"image_fills_pin":canvas.frame==root.bounds,
                "image_aspect_preserved":abs(window.frame.width/window.frame.height-CGFloat(annotationDocument.baseImage.width)/CGFloat(annotationDocument.baseImage.height))<0.005,
                "viewer_actions_outside_image_window":viewerRow.window !== window && viewerRow.window != nil,
                "pin_stays_floating":window.level == .floating,
                "output_keeps_source_pixels":stableImage()?.width==annotationDocument.baseImage.width && stableImage()?.height==annotationDocument.baseImage.height]
        if let panel = pinChrome.primary.contentView {
            let viewer = panel.convert(viewerRow.bounds, from: viewerRow)
            checks["viewer_panel_has_side_padding"] = viewer.minX >= 14 && panel.bounds.maxX - viewer.maxX >= 14
        }
        checks["viewer_has_only_three_actions"] = viewerRow.arrangedSubviews.compactMap{$0 as? NSButton}.map(\.title)==["编辑","保存","关闭"]
        checks["focus_shows_viewer_actions"] = pinChrome.primary.isVisible
        toggleEditing()
        checks["editing_keeps_image_frame"] = editing && window.frame==original && canvas.frame==root.bounds
        for tool in [AnnotationTool.arrow,.rectangle,.text,.pen,.mask,.highlight,.number] {
            canvas.chooseTool(tool);layoutPin()
            let optionsExpected = tool == .arrow || tool == .rectangle
            checks["floating_options_\(tool.title)"] = markupRow.isHidden != optionsExpected
                && pinChrome.secondary.isVisible == optionsExpected && window.frame == original
        }
        canvas.chooseTool(.text)
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(canvas)
        let local=CGPoint(x:canvas.bounds.width*0.2,y:canvas.bounds.height*0.6)
        let mouse=NSEvent.mouseEvent(with:.leftMouseDown,location:canvas.convert(local,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        canvas.mouseDown(with:mouse)
        checks["pin_text_keeps_direct_outputs"] = canvas.textEditor != nil && !saveButton.isHidden
        if let input=canvas.textEditor {
            input.setMarkedText("zhongwen",selectedRange:NSRange(location:8,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            checks["pin_candidate_blocks_output"] = !prepareOutput() && annotationDocument.state.objects.isEmpty
            input.insertText("中文",replacementRange:input.markedRange());input.unmarkText()
            checks["pin_confirmed_text_commits_for_output"] = prepareOutput() && annotationDocument.state.objects.first?.text=="中文" && stableImage()?.width==annotationDocument.baseImage.width
        }
        annotationDocument.undo();canvas.chooseTool(.select);toggleEditing()
        await recognitionForVerification?.value
        checks["return_to_view_preserves_size"] = !editing && window.frame==original && canvas.frame==root.bounds
        var textPoint:CGPoint?
        for y in stride(from:8.0,to:Double(canvas.bounds.height),by:12) {
            for x in stride(from:8.0,to:Double(canvas.bounds.width),by:12) {
                let point=CGPoint(x:x,y:y)
                if canvas.canStartTextSelection?(point)==true {textPoint=point;break}
            }
            if textPoint != nil {break}
        }
        checks["text_hit_goes_to_selection_layer"] = textPoint.map {canvas.hitTest($0) !== canvas} ?? false
        let blank=CGPoint(x:canvas.bounds.maxX-3,y:3)
        checks["blank_hit_allows_window_drag"] = canvas.canStartTextSelection?(blank)==false && canvas.hitTest(blank) === canvas
        let sourceSample=stableImage().flatMap {PixelSampler.color(in:$0,x:0,y:0)}
        window.alphaValue=0.25
        checks["view_opacity_does_not_change_export"] = stableImage().flatMap {PixelSampler.color(in:$0,x:0,y:0)}==sourceSample
        window.alphaValue=1;zoom(1.2)
        checks["zoom_preserves_aspect_and_pixels"] = abs(window.frame.width/window.frame.height-canvas.imageSize.width/canvas.imageSize.height)<0.005 && stableImage()?.width==annotationDocument.baseImage.width
        window.setFrame(original,display:true);layoutPin()
        checks["text_hit_after_zoom_restore"] = textPoint.map {canvas.canStartTextSelection?($0)==true && canvas.hitTest($0) !== canvas} ?? false
        status.stringValue="保存失败，请重试"
        checks["real_error_has_visible_feedback"] = !status.isHidden && pinChrome.secondary.isVisible
        status.stringValue=contextualStatus;layoutPin()
        let other=AnnotationWindow(contentRect:CGRect(x:0,y:0,width:120,height:80),styleMask:.titled,backing:.buffered,defer:false)
        other.isReleasedWhenClosed=false;other.makeKeyAndOrderFront(nil)
        let exit=NSEvent.enterExitEvent(with:.mouseExited,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,trackingNumber:1,userData:nil)!
        for surface in [root,pinChrome.primary.contentView,pinChrome.secondary.contentView].compactMap({$0 as? PinSurface}) {surface.mouseExited(with:exit)}
        pinChrome.refreshVisibility();try? await Task.sleep(for:.milliseconds(300))
        checks["actions_hide_without_focus_or_hover"] = !pinChrome.primary.isVisible && !pinChrome.secondary.isVisible
        window.makeKeyAndOrderFront(nil);other.close();pinChrome.refreshVisibility()
        checks["focus_restores_actions"] = pinChrome.primary.isVisible
        return checks
    }
    func windowCaptureLayoutChecks(region:CGRect,pixels:CGSize)->[String:Bool] {
        guard let root=screenshotView else {return ["uses_inline_editor":false]}
        root.layoutSubtreeIfNeeded();layoutScreenshot()
        let output=stableImage(),base=annotationDocument.baseImage
        let samePixels=output.map {image in [(0,0),(base.width/2,base.height/2),(base.width-1,base.height-1)].allSatisfy {point in PixelSampler.color(in:image,x:point.0,y:point.1)==PixelSampler.color(in:base,x:point.0,y:point.1)}} ?? false
        let scale=min(root.bounds.width/root.presentation.captureSize.width,root.bounds.height/root.presentation.captureSize.height)
        let mapped=CGRect(x:(root.bounds.width-root.presentation.captureSize.width*scale)/2+region.minX*scale,y:(root.bounds.height-root.presentation.captureSize.height*scale)/2+region.minY*scale,width:region.width*scale,height:region.height*scale)
        return ["uses_inline_editor":isScreenshot,"complete_window_placement":root.region==region && canvas.frame==mapped,
                "window_capture_has_no_recrop_handles":!root.canAdjust,"output_keeps_complete_window_pixels":output?.width==Int(pixels.width) && output?.height==Int(pixels.height),
                "output_pixel_samples_match_window":samePixels,"toolbar_visible_and_inside_screen":toolbarPanel.map {!$0.isHidden && root.bounds.contains($0.frame)} ?? false]
    }
    func inlineLayoutChecks(previewPath: String? = nil)->[String:Bool] {
        guard let root=screenshotView,let toolbarPanel,let parametersPanel else {return [:]}
        root.layoutSubtreeIfNeeded();layoutScreenshot()
        var checks:[String:Bool]=[:]
        let original=root.region
        checks["canvas_keeps_original_region"] = canvas.frame == original && canvas.contentRect == canvas.bounds
        let image=stableImage()
        checks["output_contains_only_crop"] = image?.width == 716 && image?.height == 450 && image.flatMap {PixelSampler.color(in:$0,x:20,y:420)?.hex} == "#FF0000"
        checks["output_png_excludes_chrome_and_background"] = image.flatMap {Self.encoded($0,type:.png)}.flatMap {CGImageSourceCreateWithData($0 as CFData,nil)}.flatMap {CGImageSourceCreateImageAtIndex($0,0,nil)}.map {$0.width==716 && $0.height==450} == true
        let primaryFrame=toolbarPanel.frame
        checks["toolbar_is_below_region"] = primaryFrame.maxY < original.minY
        let toolbarRow = toolbarPanel.convert(toolRow.bounds, from: toolRow)
        checks["toolbar_has_side_padding"] = toolbarRow.minX >= 14 && toolbarPanel.bounds.maxX - toolbarRow.maxX >= 14
        let buttons = toolRow.arrangedSubviews.compactMap { $0 as? ToolbarButton }
        if let scroll = toolbarContent?.subviews.compactMap({ $0 as? NSScrollView }).first, let document = scroll.documentView {
            let visible = scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5)
            checks["toolbar_does_not_clip_button_backgrounds"] = buttons.allSatisfy {
                visible.contains(document.convert($0.bounds, from: $0))
            }
        }
        checks["toolbar_button_contents_are_centered"] = buttons.allSatisfy { button in
            let frames = button.contentFrames(in: button.bounds)
            let content = frames.icon.isEmpty ? frames.title : frames.title.isEmpty ? frames.icon : frames.icon.union(frames.title)
            let sideSpace = button.bounds.maxX - content.maxX
            return abs(content.minX - button.bounds.minX - sideSpace) < 0.5 && sideSpace >= 8
        }
        checks["completion_has_fixed_label"] = copyButton.title == "完成"
        checks["all_tools_and_outputs_fit_toolbar"] = toolRow.arrangedSubviews.filter { !$0.isHidden }.allSatisfy {
            toolbarPanel.bounds.contains(toolbarPanel.convert($0.bounds, from: $0))
        }
        for tool in [AnnotationTool.arrow, .rectangle, .text, .pen, .mask, .highlight, .number] {
            canvas.chooseTool(tool);root.layoutSubtreeIfNeeded();layoutScreenshot()
            let optionsExpected = tool == .arrow || tool == .rectangle
            checks["compact_parameters_\(tool.title)"] = optionsExpected
                ? !parametersPanel.isHidden && parametersPanel.frame.maxY < toolbarPanel.frame.minY && root.bounds.contains(parametersPanel.frame)
                : parametersPanel.isHidden
            checks["stable_region_\(tool.title)"] = canvas.frame == original && toolbarPanel.frame == primaryFrame
        }
        canvas.chooseTool(.arrow)
        checks["curved_open_arrow_is_default"] = arrowSamples[1].state == .on && canvas.currentStyle.arrowHead == .open && !canvas.currentStyle.dashed
        checks["samples_have_no_visible_titles"] = arrowSamples.allSatisfy { $0.title.isEmpty && $0.image != nil && !$0.isHidden }
        func drawArrow(from start: CGPoint, to end: CGPoint) {
            for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
                let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                                               timestamp: 0, windowNumber: window!.windowNumber, context: nil,
                                               eventNumber: 1, clickCount: 1, pressure: 1)!
                if type == .leftMouseDown { canvas.mouseDown(with: event) }
                else if type == .leftMouseDragged { canvas.mouseDragged(with: event) }
                else { canvas.mouseUp(with: event) }
            }
        }
        drawArrow(from: CGPoint(x: 150, y: 300), to: CGPoint(x: 345, y: 200))
        checks["drawing_uses_default_curve_and_coral"] = canvas.selected?.curveControl != nil
            && canvas.selected?.style.color == AnnotationColor.markupPalette[0]
        if let previewPath, let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: previewPath))
        }
        arrowSamples[0].performClick(nil)
        markupSwatches[2].performClick(nil)
        checks["style_buttons_update_existing_arrow"] = canvas.selected?.curveControl == nil
            && canvas.selected?.style.color == AnnotationColor.markupPalette[2]
        annotationDocument.undo();annotationDocument.undo()
        checks["undo_restores_original_arrow"] = canvas.selected?.curveControl != nil
            && canvas.selected?.style.color == AnnotationColor.markupPalette[0]
        annotationDocument.undo()
        canvas.chooseTool(.rectangle)
        checks["rectangle_only_has_three_colors"] = markupSwatches.allSatisfy { !$0.isHidden }
            && arrowSamples.allSatisfy { $0.isHidden }
        canvas.chooseTool(.text)
        let point=CGPoint(x:100,y:230)
        let event=NSEvent.mouseEvent(with:.leftMouseDown,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        canvas.mouseDown(with:event)
        checks["text_keeps_direct_outputs"] = canvas.textEditor != nil && !copyButton.isHidden && !saveButton.isHidden && !pinButton.isHidden
        if let input=canvas.textEditor {
            input.setMarkedText("zhongwen",selectedRange:NSRange(location:8,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
            checks["candidate_blocks_output_commit"] = !prepareOutput() && canvas.textEditor === input && annotationDocument.state.objects.isEmpty
            input.insertText("中文",replacementRange:input.markedRange());input.unmarkText()
            checks["confirmed_text_commits_for_output"] = prepareOutput() && annotationDocument.state.objects.first?.text == "中文" && stableImage()?.width==716
        }
        checks["annotations_disable_crop_handles"] = !root.canAdjust
        annotationDocument.undo();canvas.chooseTool(.select);layoutScreenshot()
        checks["undo_restores_crop_handles"] = root.canAdjust && annotationDocument.state.objects.isEmpty
        let down=NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:original.maxX,y:original.minY),modifierFlags:[],timestamp:0,windowNumber:window!.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        root.mouseDown(with:down)
        checks["adjustment_blocks_old_output"] = root.isAdjusting && stableImage()==nil && overlay.analysis==nil
        root.cancelOperation(nil)
        checks["cancel_adjustment_preserves_image"] = !root.isAdjusting && root.region==original && stableImage()?.width==716 && !canvas.isHidden
        preserveScreenshotAfterScreenChange()
        checks["screen_change_preserves_crop_and_disables_recrop"] = !root.sourceGeometryAvailable && !root.canAdjust && stableImage()?.width==716 && stableImage()?.height==450
        return checks
    }
    func screenshotOutputChecks() async -> [String: Bool] {
        guard let window = window as? AnnotationWindow else { return [:] }
        await recognitionForVerification?.value
        status.stringValue = contextualStatus
        let copyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                         characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        var checks: [String: Bool] = [:]
        checks["copy_image_keeps_editor_open"] = window.performKeyEquivalent(with: copyEvent)
            && pasteboard.data(forType: .png) != nil && !closed
        let text = overlay.text
        selectAll(nil)
        checks["copy_selected_text_keeps_editor_open"] = !text.isEmpty && window.performKeyEquivalent(with: copyEvent)
            && pasteboard.string(forType: .string) == text && !closed
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        if (try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)) != nil {
            defer { try? FileManager.default.removeItem(at: temporary) }
            preferences.setSaveDirectory(temporary)
            saveImage()
            let panel = window.attachedSheet as? NSSavePanel
            checks["save_uses_system_picker_at_default_folder"] = panel?.directoryURL?.standardizedFileURL.path == temporary.standardizedFileURL.path
                && panel?.canCreateDirectories == true
            panel?.cancel(nil)
            checks["cancel_does_not_modify_default_folder"] = preferences.saveDirectory?.standardizedFileURL.path == temporary.standardizedFileURL.path
            try? await Task.sleep(for: .milliseconds(300))
        }
        copyButton.performClick(nil)
        checks["finish_copies_text_and_closes_editor"] = closed && !text.isEmpty && pasteboard.string(forType: .string) == text
        return checks
    }
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
        canvas.chooseTool(.arrow); root.layoutSubtreeIfNeeded()
        result["arrow_selection_reveals_style_without_extra_click"] = !styleRow.isHidden && !optionRow.isHidden && !arrowPicker.isHidden && !arrowTitle.isHidden
        result["arrow_defaults_to_open_head"] = canvas.currentStyle.arrowHead == .open && arrowPicker.selectedSegment == 1
        status.stringValue = "拖选文字后 ⌘C 复制"; updateControls()
        result["drawing_does_not_offer_text_selection"] = !status.stringValue.contains("拖选文字")
        let initialArrowStyle = canvas.currentStyle
        strokeWidthField.stringValue = "12"; changeStrokeWidth()
        result["compact_stroke_controls"] = widthSlider.isHidden && !strokeWidthField.isHidden && presetButtons.filter { !$0.isHidden }.count == 3 && canvas.currentStyle.width == 12
        strokeWidthField.stringValue = "0"; changeStrokeWidth()
        result["invalid_stroke_width_keeps_value"] = canvas.currentStyle.width == 12 && strokeWidthField.stringValue == "12"
        strokeWidthField.stringValue = "12"; changeStrokeWidth()
        result["corrected_stroke_width_clears_own_error"] = !status.stringValue.contains("线宽须为")
        status.stringValue = "保存失败，请重试"; changeStrokeWidth()
        result["stroke_input_keeps_unrelated_error"] = status.stringValue == "保存失败，请重试"
        arrowPicker.selectedSegment = 0; arrowPicker.sendAction(arrowPicker.action,to:arrowPicker.target)
        dashButton.selectedSegment = 1; dashButton.sendAction(dashButton.action,to:dashButton.target)
        result["style_preview_controls_change_arrow_and_line"] = canvas.currentStyle.arrowHead == .filled && canvas.currentStyle.dashed && arrowPicker.image(forSegment:0) != nil && dashButton.image(forSegment:1) != nil
        canvas.changeStyle(initialArrowStyle)
        result["style_panel_stays_in_window"] = !styleRow.isHidden && root.bounds.contains(root.convert(styleRow.bounds,from:styleRow)) && root.bounds.contains(root.convert(optionRow.bounds,from:optionRow))
        canvas.chooseTool(.rectangle); root.layoutSubtreeIfNeeded()
        result["rectangle_selection_replaces_arrow_options"] = !styleRow.isHidden && arrowPicker.isHidden && !fillButton.isHidden && !cornerSlider.isHidden
        canvas.chooseTool(.text); root.layoutSubtreeIfNeeded()
        result["text_selection_reveals_font_options"] = !styleRow.isHidden && widthTitle.stringValue == "字号" && !boldButton.isHidden && !textBackground.isHidden && arrowPicker.isHidden
        let originalTextStyle = canvas.currentStyle
        fontSizeField.stringValue = "32"; fontSizeField.sendAction(fontSizeField.action,to:fontSizeField.target)
        result["font_input_changes_size"] = canvas.currentStyle.fontSize == 32 && widthSlider.isHidden && presetButtons.allSatisfy { $0.isHidden } && !fontSizeField.isHidden
        fontSizeField.stringValue = "abc"; changeFontSize()
        result["invalid_font_size_keeps_value"] = canvas.currentStyle.fontSize == 32 && fontSizeField.stringValue == "32"
        fontSizeField.stringValue = "24"; changeFontSize()
        result["corrected_font_size_clears_own_error"] = canvas.currentStyle.fontSize == 24 && !status.stringValue.contains("字号须为")
        boldButton.performClick(nil); textBackground.performClick(nil)
        result["compact_text_controls_change_style"] = canvas.currentStyle.bold != originalTextStyle.bold && canvas.currentStyle.textBackground != originalTextStyle.textBackground && optionRow.isHidden && !paletteTray.isHidden
        canvas.changeStyle(originalTextStyle)
        let originalState = annotationDocument.state
        var textState = originalState
        let longText = AnnotationObject(tool:.text,style:.initial(.text),start:CGPoint(x:20,y:20),end:CGPoint(x:220,y:120),text:"第一行\n第二行\n第三行",textLayoutWidth:200)
        textState.objects.append(longText); annotationDocument.commit(textState)
        canvas.chooseTool(.select)
        let imagePoint = CGPoint(x:50,y:50), rect = canvas.contentRect
        let viewPoint = CGPoint(x:rect.minX+imagePoint.x/CGFloat(annotationDocument.baseImage.width)*rect.width,y:rect.minY+imagePoint.y/CGFloat(annotationDocument.baseImage.height)*rect.height)
        func selectionEvent(_ type: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with:type,location:canvas.convert(viewPoint,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)! }
        canvas.mouseDown(with:selectionEvent(.leftMouseDown)); canvas.mouseUp(with:selectionEvent(.leftMouseUp))
        fontSizeField.stringValue = "0"; changeFontSize()
        fontSizeField.stringValue = "200"; changeFontSize()
        result["corrected_range_keeps_new_layout_error"] = canvas.selected?.id == longText.id && canvas.currentStyle.fontSize == 24 && status.stringValue == "文字超出截图，请调小字号"
        canvas.chooseTool(.select); annotationDocument.commit(originalState)
        root.layoutSubtreeIfNeeded()
        result["selection_hides_irrelevant_style_controls"] = styleRow.isHidden && optionRow.isHidden
        copyButton.title = previousCopyTitle
        window.setFrame(original,display:true); root.layoutSubtreeIfNeeded()
        return result
    }
}
