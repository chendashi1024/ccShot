import AppKit
import Carbon
import ScreenCaptureKit
import QuartzCore

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var selectionWindow: SelectionWindow?
    private var imageWindows: [UUID: ImageWindow] = [:]
    private let hotkeys = HotkeyManager()
    private let preferences = AppPreferences.shared
    private var settings: SettingsWindow?
    private var editorsHiddenForSettings:[UUID]=[]
    private var hotkeyWarning: NSMenuItem?
    private var captureTask: Task<Void, Never>?
    private var fixture: CGImage?
    private var verificationPreferencesSuite: String?
    private var captureGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let appearance = argument("--appearance") { NSApp.appearance = NSAppearance(named:appearance == "light" ? .aqua : .darkAqua) }
        let menu = NSMenu()
        for (title, action, key) in [("区域截图", #selector(capture), ""), ("钉住剪贴板", #selector(pinClipboard), ""), ("设置…", #selector(openSettings), ","), ("退出 ccShort", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.setAccessibilityLabel("ccShort")
            button.toolTip = "ccShort"
            if let iconURL = Bundle.main.url(forResource: "StatusIcon", withExtension: "pdf"),
               let icon = NSImage(contentsOf: iconURL) {
                icon.isTemplate = true
                button.image = icon
                button.imagePosition = .imageOnly
            } else {
                button.title = "ccShort"
            }
        }
        statusItem.menu = menu
        let main = NSMenu()
        let appMenu = NSMenuItem(); appMenu.submenu = menu.copy() as? NSMenu; main.addItem(appMenu)
        let edit = NSMenuItem(); edit.submenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(ImageWindow.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSResponder.selectAll(_:)), "a"), ("保存", #selector(ImageWindow.saveDocument(_:)), "s")] {
            edit.submenu?.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        edit.submenu?.addItem(.separator())
        edit.submenu?.addItem(withTitle: "撤销", action: #selector(ImageWindow.undo(_:)), keyEquivalent: "z")
        let redo = edit.submenu?.addItem(withTitle: "重做", action: #selector(ImageWindow.redo(_:)), keyEquivalent: "z"); redo?.keyEquivalentModifierMask = [.command, .shift]
        let allText = edit.submenu?.addItem(withTitle: "复制全部文字", action: #selector(ImageWindow.copyAllText), keyEquivalent: "c"); allText?.keyEquivalentModifierMask = [.command, .shift]
        edit.submenu?.addItem(withTitle: "钉图", action: #selector(ImageWindow.pinImage), keyEquivalent: "t")
        main.addItem(edit); NSApp.mainMenu = main
        registerHotkeys()
        if let path = argument("--fixture"), let image = Self.loadImage(URL(fileURLWithPath: path)) {
            fixture = image
            if let path = argument("--display-smoke-test"),let host=argument("--display-fixture-host") {Task { @MainActor in exit(await DisplayVerification.run(fixture:argument("--fixture")!,host:host,reportPath:path)) }}
            else if let path = argument("--screen-smoke-test") { Task { @MainActor in exit(await ScreenVerification.run(image,reportPath:path)) } }
            else if CommandLine.arguments.contains("--permission-guide") { showPermissionGuide(); showImage(image,pinned:false) }
            else if let path = argument("--fixture-save-directory") {
                let suite="com.ccshot.save-check.\(UUID().uuidString)"; verificationPreferencesSuite=suite
                let store = UserDefaults(suiteName:suite)!
                store.setVolatileDomain([AppPreferences.directoryKey:path],forName:UserDefaults.argumentDomain)
                showDocument(AnnotationDocument(image:image),pinned:false,preferences:AppPreferences(store:store))
            }
            else if let path=argument("--pin-smoke-test") {Task { @MainActor in let keep=CommandLine.arguments.contains("--keep-pin-preview");let passed=await PinVerification.run(image:image,reportPath:path,keepPreview:keep);if !keep {exit(passed ? 0 : 1)} }}
            else if let path=argument("--window-inline-smoke-test") {Task { @MainActor in let passed=await InlineVerification.runWindow(reportPath:path,preview:CommandLine.arguments.contains("--keep-window-preview"));if !CommandLine.arguments.contains("--keep-window-preview") {exit(passed ? 0 : 1)} }}
            else if let path=argument("--inline-smoke-test") {Task { @MainActor in exit(await InlineVerification.run(reportPath:path, previewPath:argument("--inline-preview")) ? 0 : 1) }}
            else if let path = argument("--text-smoke-test") { Task { @MainActor in exit(await TextVerification.run(reportPath:path, previewPath:argument("--text-preview")) ? 0 : 1) } }
            else if let path = argument("--privacy-smoke-test") { Task { @MainActor in exit(await PrivacyVerification.run(reportPath:path, previewPath:argument("--privacy-preview"),checkClipboard:!CommandLine.arguments.contains("--no-clipboard")) ? 0 : 1) } }
            else if let report = argument("--window-smoke-test") { runWindowCaptureTest(image, report: report) }
            else if let path = argument("--render-annotations") { Task { @MainActor in exit(await ImageWindow.annotationPreview(image, to: path) ? 0 : 1) } }
            else if let path = argument("--render-settings") { Task { @MainActor in await renderSettings(to:path) } }
            else if let previewPath = argument("--render-window-highlight") { renderSelection(image, to: previewPath, windowHighlight: true) }
            else if let previewPath = argument("--render-selection") { renderSelection(image, to: previewPath) }
            else if argument("--smoke-test") != nil { runSmokeTest(image) }
            else if CommandLine.arguments.contains("--select") { capture() }
            else { showImage(image, pinned: false) }
        }
        if fixture == nil && CommandLine.arguments.contains("--capture-now") { capture() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let path=argument("--benchmark-report"),let mode=argument("--benchmark-mode"),let fixtures=argument("--benchmark-fixtures") {
            Task { @MainActor in
                let result=await PerformanceVerification.run(mode:mode,reportPath:path,fixtureDirectory:fixtures,controller:self,displayHost:argument("--benchmark-display-host"))
                hotkeys.shutdown();exit(result)
            }
        }
    }
    func performanceReadyState() -> [String:Any] {
        statusItem.button?.window?.displayIfNeeded();CATransaction.flush()
        let ready=statusItem.button?.window != nil && statusItem.menu != nil && hotkeys.activeCount>0 && hotkeyWarning==nil
        return ["ready":ready,"status_button_attached":statusItem.button?.window != nil,"registered_hotkeys":hotkeys.activeCount,"hotkey_warning":hotkeyWarning != nil]
    }
    func performanceSelectionObservation() -> [String:Any]? {
        guard let window=selectionWindow,let view=window.contentView as? SelectionView else {return nil}
        window.displayIfNeeded();CATransaction.flush()
        let submitted=ProcessInfo.processInfo.systemUptime
        let image=view.image,sx=CGFloat(image.width)/view.bounds.width,sy=CGFloat(image.height)/view.bounds.height
        func pixel(_ x:CGFloat,_ y:CGFloat)->SampledColor? {PixelSampler.color(in:image,x:Int(x*sx),y:image.height-1-Int(y*sy))}
        let a=pixel(25,25),b=pixel(view.bounds.width-25,25),c=pixel(25,view.bounds.height-25),d=pixel(view.bounds.width-25,view.bounds.height-25)
        let fixture=(a.map{$0.red>180 && $0.green<130 && $0.blue<130} ?? false) && (b.map{$0.green>180 && $0.red<130 && $0.blue<130} ?? false) && (c.map{$0.blue>180 && $0.red<130 && $0.green<130} ?? false) && (d.map{$0.red>180 && $0.green>180 && $0.blue<130} ?? false)
        return ["ready":window.isVisible && window.isKeyWindow && window.firstResponder === view,"submitted_uptime":submitted,"width":image.width,"height":image.height,"fixture_corners_valid":fixture]
    }
    func performanceCloseSelection() {cancelCapture()}
    private func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    private func registerHotkeys() {
        hotkeys.onAction = { [weak self] action in
            switch action {
            case .capture: self?.capture()
            case .pin: self?.pinCurrentOrClipboard()
            }
        }
        updateHotkeyWarning(hotkeys.apply(capture: preferences.captureShortcut, pin: preferences.pinShortcut))
    }
    private func updateHotkeyWarning(_ error: String?) {
        if let hotkeyWarning { statusItem.menu?.removeItem(hotkeyWarning) }
        hotkeyWarning = nil
        if let error {
            let warning = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            statusItem.menu?.addItem(warning)
            hotkeyWarning = warning
        }
    }
    @objc private func openSettings() {
        // 暂藏框选而不丢掉快照，关闭设置后可继续当前截图。
        captureGeneration += 1
        captureTask?.cancel(); captureTask = nil
        selectionWindow?.orderOut(nil)
        for (id,controller) in imageWindows where controller.isScreenshot && controller.window?.isVisible == true {
            if !editorsHiddenForSettings.contains(id) {editorsHiddenForSettings.append(id)}
            controller.suspendScreenshotForSettings()
        }
        if settings == nil {
            settings = SettingsWindow(preferences: preferences, applyShortcuts: { [weak self] capture, pin in
                guard let self else { return "应用已关闭" }
                let error = self.hotkeys.apply(capture: capture, pin: pin)
                self.updateHotkeyWarning(error)
                return error
            }, recordingChanged: { [weak self] recording in
                guard let self else { return "应用已关闭" }
                if recording { self.hotkeys.pause(); return nil }
                let error = self.hotkeys.apply(capture: self.preferences.captureShortcut, pin: self.preferences.pinShortcut)
                self.updateHotkeyWarning(error)
                return error
            })
            settings?.onClose = { [weak self] in
                guard let self else {return}
                for id in self.editorsHiddenForSettings {self.imageWindows[id]?.window?.makeKeyAndOrderFront(nil)}
                self.editorsHiddenForSettings=[]
                guard let window = self.selectionWindow else { return }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(window.contentView)
            }
        }
        settings?.present()
    }
    @objc func capture() {
        cancelCapture()
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        if let fixture { presentSelection(Self.fixtureBackground(fixture,on:screen), on: screen); return }
        guard CGPreflightScreenCaptureAccess() else {
            showPermissionGuide()
            return
        }
        let token = captureGeneration
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await DisplayCapture.capture(screen:screen)
                guard !Task.isCancelled, token == captureGeneration else { return }
                presentSelection(snapshot.image, on:screen, targets:snapshot.targets)
            } catch {
                guard !Task.isCancelled, token == captureGeneration else { return }
                showError("无法截取屏幕", detail: "请检查屏幕录制权限后重试。")
            }
        }
    }
    // 测试样本按屏幕等比排版，避免宽幅识字样本被拉伸，真实屏幕捕获不经过这里。
    private static func fixtureBackground(_ image:CGImage,on screen:NSScreen)->CGImage {
        let size=screen.frame.size,scale=screen.backingScaleFactor
        guard let context=CGContext(data:nil,width:Int(size.width*scale),height:Int(size.height*scale),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return image}
        context.scaleBy(x:scale,y:scale);context.setFillColor(NSColor(srgbRed:0.84,green:0.88,blue:0.85,alpha:1).cgColor);context.fill(CGRect(origin:.zero,size:size))
        let ratio=min(size.width/CGFloat(image.width),size.height/CGFloat(image.height))
        let frame=CGRect(x:(size.width-CGFloat(image.width)*ratio)/2,y:(size.height-CGFloat(image.height)*ratio)/2,width:CGFloat(image.width)*ratio,height:CGFloat(image.height)*ratio)
        context.draw(image,in:frame);return context.makeImage() ?? image
    }
    private func presentSelection(_ image: CGImage, on screen: NSScreen, targets: [WindowTarget] = []) {
        let sourceFrame=screen.frame
        let sourceDisplayID=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "ccShort · 框选"
        window.level = .screenSaver
        window.isOpaque = true
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(image: image, frame: CGRect(origin: .zero, size: screen.frame.size))
        view.windowTargets = targets;view.automaticallyEdit=true
        view.onWindowPick = { [weak self, weak view,weak window] target in
            guard let self,let view,let window,self.selectionWindow === window else { return }
            view.showWindowStatus("正在捕获窗口…")
            self.captureTask?.cancel()
            let token = self.captureGeneration
            self.captureTask = Task { @MainActor [weak self, weak view,weak window] in
                guard let self else { return }
                do {
                    let captured = try await WindowCapture.captureSnapshot(id: target.id, ownerPID: target.ownerPID)
                    guard !Task.isCancelled,token == self.captureGeneration,let window,self.selectionWindow === window else {return}
                    guard let primaryTop=NSScreen.screens.first?.frame.maxY,
                          NSScreen.screens.contains(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == sourceDisplayID && $0.frame == sourceFrame}),
                          let region=WindowTarget.editorRect(quartzFrame:captured.quartzFrame,screenFrame:sourceFrame,primaryTop:primaryTop) else {throw WindowCapture.CaptureError.missing}
                    let context=ScreenshotPresentation(background:image,screenFrame:sourceFrame,region:region,displayID:sourceDisplayID,allowsAdjustment:false)
                    self.cancelCapture()
                    self.showDocument(AnnotationDocument(image:captured.image),pinned:false,screenshot:context)
                } catch {
                    guard !Task.isCancelled, token == self.captureGeneration else { return }
                    view?.showWindowStatus("窗口已关闭或无法捕获，请重新选择或拖动截图区域")
                }
            }
        }
        view.onConfirm = { [weak self,weak window] selected, rect, action in
            guard let self,let window,self.selectionWindow === window else {return}
            let local=rect.offsetBy(dx:-sourceFrame.minX,dy:-sourceFrame.minY)
            let context=ScreenshotPresentation(background:image,screenFrame:sourceFrame,region:local,displayID:sourceDisplayID,allowsAdjustment:true)
            let image=selected
            self.cancelCapture()
            switch action {
            case .edit: self.showDocument(AnnotationDocument(image:image),pinned:false,screenshot:context)
            case .annotate(let tool): self.showDocument(AnnotationDocument(image:image),pinned:false,screenshot:context).canvas.chooseTool(tool)
            case .pin: self.showImage(image, pinned: true)
            case .save: self.showDocument(AnnotationDocument(image:image),pinned:false,screenshot:context).saveImage()
            case .copy:
                guard let data = ImageWindow.encoded(image, type: .png) else {
                    self.showImage(image, pinned: false)
                    self.showError("图片编码失败", detail: "截图仍然保留，请重试。")
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if !pasteboard.setData(data, forType: .png) {
                    self.showImage(image, pinned: false)
                    self.showError("复制失败", detail: "截图仍然保留，请重试。")
                }
            }
        }
        view.onCancel = { [weak self,weak window] in guard let self,let window,self.selectionWindow === window else {return};self.cancelCapture() }
        window.contentView = view
        selectionWindow = window
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func cancelCapture() {
        captureGeneration += 1
        captureTask?.cancel(); captureTask = nil
        selectionWindow?.close(); selectionWindow = nil
    }
    @objc private func screenChanged() {
        let hadSelection = selectionWindow != nil
        cancelCapture()
        for controller in imageWindows.values {controller.preserveScreenshotAfterScreenChange()}
        if hadSelection { showError("屏幕已变化", detail: "请重新开始截图。") }
    }
    @discardableResult private func showImage(_ image: CGImage, pinned: Bool) -> ImageWindow {
        return showDocument(AnnotationDocument(image: image), pinned: pinned)
    }
    @discardableResult private func showDocument(_ document: AnnotationDocument, pinned: Bool, preferences: AppPreferences = .shared, screenshot:ScreenshotPresentation?=nil,pinFrame:CGRect?=nil) -> ImageWindow {
        let id = UUID()
        let controller = ImageWindow(annotationDocument: document, pinned:pinned,preferences:preferences,screenshot:screenshot,pinFrame:pinFrame)
        controller.onClose = { [weak self] in self?.imageWindows.removeValue(forKey: id) }
        controller.onPin = { [weak self,weak controller] document in self?.showDocument(document,pinned:true,pinFrame:controller?.suggestedPinFrame) }
        controller.onReselect = { [weak self,weak controller] rect in
            guard let self,let controller,self.imageWindows[id] === controller,let screenshot,
                  screenshot.allowsAdjustment,controller.annotationDocument.state.objects.isEmpty,!controller.canvas.hasDraft,
                  NSScreen.screens.contains(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenshot.displayID && $0.frame == screenshot.screenFrame}),
                  let pixels=CaptureGeometry.pixelRect(rect,canvas:screenshot.captureSize,image:CGSize(width:screenshot.background.width,height:screenshot.background.height)),
                  let image=screenshot.background.cropping(to:pixels) else {return false}
            controller.close()
            self.showDocument(AnnotationDocument(image:image),pinned:false,preferences:preferences,screenshot:screenshot.replacingRegion(rect))
            return true
        }
        imageWindows[id] = controller
        return controller
    }
    @objc private func pinClipboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), let image = Self.loadImage(data) {
            showImage(image, pinned: true)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.labelColor]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let box = attributed.boundingRect(with: NSSize(width: 650, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading])
            let size = NSSize(width: max(180, min(700, ceil(box.width) + 40)), height: max(80, min(4040, ceil(box.height) + 40)))
            let rendered = NSImage(size: size)
            rendered.lockFocus()
            NSColor.textBackgroundColor.setFill(); NSRect(origin: .zero, size: size).fill()
            attributed.draw(with: NSRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40), options: [.usesLineFragmentOrigin, .usesFontLeading])
            rendered.unlockFocus()
            if let image = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) { showImage(image, pinned: true) }
        } else { showError("剪贴板中没有图片或文字", detail: "先复制内容，再使用钉图。") }
    }
    private func pinCurrentOrClipboard() {
        if let selection = selectionWindow?.contentView as? SelectionView { selection.pinSelection() }
        else if let editor = imageWindows.values.first(where: { $0.window?.isKeyWindow == true }) { editor.pinImage() }
        else { pinClipboard() }
    }
    private func showPermissionGuide() {
        let alert = NSAlert(); alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请允许当前的 ccShort 录制屏幕。授权后重新打开 ccShort，再开始截图。"
        alert.addButton(withTitle: "请求授权")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "暂不")
        NSApp.activate(ignoringOtherApps:true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if CGRequestScreenCaptureAccess(), CGPreflightScreenCaptureAccess() { capture() }
            return
        case .alertSecondButtonReturn:
            break
        default:
            return
        }
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
           NSWorkspace.shared.open(pane) { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences") else {
            showError("无法打开系统设置",detail:"请从苹果菜单打开系统设置，进入隐私与安全性。")
            return
        }
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
    }
    private func showError(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    private static func loadImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    private func runSmokeTest(_ image: CGImage) {
        let settingsSmoke = runSettingsSmokeTest()
        let repeatBindingPassed = hotkeys.apply(capture: preferences.captureShortcut, pin: preferences.pinShortcut) == nil
        let fallbackBindingPassed = hotkeys.apply(capture: .fallback, pin: preferences.pinShortcut) == nil && hotkeys.activeCount == 2
        let restoredAfterFallback = hotkeys.apply(capture: preferences.captureShortcut, pin: preferences.pinShortcut) == nil
        let previousBindingCount = hotkeys.activeCount
        let occupied = AppShortcut(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), keyName: "X")
        var foreign: EventHotKeyRef?
        let conflictStatus = RegisterEventHotKey(occupied.keyCode, occupied.modifiers, EventHotKeyID(signature: 0x54455354, id: 999), GetApplicationEventTarget(), 0, &foreign)
        let conflictRejected = conflictStatus == noErr && foreign != nil && hotkeys.apply(capture: occupied, pin: preferences.pinShortcut) != nil && hotkeys.activeCount == previousBindingCount
        if let foreign { UnregisterEventHotKey(foreign) }
        let oldBindingsPreserved = conflictRejected && hotkeys.apply(capture: preferences.captureShortcut, pin: preferences.pinShortcut) == nil
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        let selector = SelectionView(image: image, frame: NSRect(x: 0, y: 0, width: 960, height: 230))
        var selected: CGImage?
        selector.onConfirm = { image, _, _ in selected = image }
        selector.selectRegion(NSRect(x: 0, y: 115, width: 480, height: 115))
        selector.confirm()
        let cropPassed = selected?.width == image.width / 2 && selected?.height == image.height / 2
        // 直接回归本视图的事件处理，不向系统注入鼠标事件。
        func mouse(_ kind: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        selector.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 480, y: 230)))
        selector.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 600, y: 200)))
        selector.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 600, y: 200)))
        selector.confirm()
        let resizePassed = selected?.width == image.width * 600 / 960 && selected?.height == image.height * 85 / 230
        selector.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 600, y: 200)))
        selector.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 700, y: 180)))
        selector.cancelOperation(nil)
        selector.confirm()
        let cancelGesturePassed = selected?.width == image.width * 600 / 960 && selected?.height == image.height * 85 / 230
        selected = nil
        selector.cancelOperation(nil)
        selector.confirm()
        var canceled = false
        selector.onCancel = { canceled = true }
        selector.cancelOperation(nil)
        let cancelSequencePassed = selected == nil && canceled
        selector.updatePointer(CGPoint(x: 480, y: 115))
        let expectedColor = PixelSampler.color(in: image, x: image.width / 2, y: image.height - 1 - image.height / 2)
        let colorKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: UInt16(kVK_ANSI_C))!
        selector.keyDown(with: colorKey)
        let hexKeyPassed = pasteboard.string(forType: .string) == expectedColor?.hex
        let rgbKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0, windowNumber: 0, context: nil, characters: "C", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: UInt16(kVK_ANSI_C))!
        selector.keyDown(with: rgbKey)
        let rgbKeyPassed = pasteboard.string(forType: .string) == expectedColor?.rgb
        selector.selectRegion(.zero)
        selector.windowTargets = [WindowTarget(id: 42, ownerPID: 10, rect: CGRect(x: 50, y: 50, width: 400, height: 150)), WindowTarget(id: 43, ownerPID: 20, rect: selector.bounds)]
        var pickedWindow: UInt32?
        selector.onWindowPick = { pickedWindow = $0.id }
        selector.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
        selector.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 100, y: 100)))
        let windowClickPassed = pickedWindow == 42
        pickedWindow = nil
        selector.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
        selector.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 350, y: 180)))
        selector.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 350, y: 180)))
        selector.confirm()
        let windowDragPassed = pickedWindow == nil && selected?.width == image.width * 250 / 960 && selected?.height == image.height * 80 / 230
        selector.selectRegion(.zero)
        selector.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
        selector.cancelOperation(nil)
        selector.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 100, y: 100)))
        let cancelWindowPassed = pickedWindow == nil
        let annotationSmoke = ImageWindow.annotationChecks(image)
        let editor = showImage(image, pinned: false)
        let pin = showImage(image, pinned: true)
        let twoWindows = imageWindows.count == 2 && pin.window?.level == .floating
        editor.copyImage()
        let writtenCount = pasteboard.changeCount
        let copyClosedEditorOnly = imageWindows.count == 1
        let png = pasteboard.data(forType: .png).flatMap(Self.loadImage)
        let jpeg = ImageWindow.encoded(image, type: .jpeg).flatMap(Self.loadImage)
        let passed = annotationSmoke.values.allSatisfy({ $0 }) && settingsSmoke.values.allSatisfy({ $0 }) && repeatBindingPassed && fallbackBindingPassed && restoredAfterFallback && oldBindingsPreserved && cropPassed && resizePassed && cancelGesturePassed && cancelSequencePassed && hexKeyPassed && rgbKeyPassed && windowClickPassed && windowDragPassed && cancelWindowPassed && png?.width == image.width && png?.height == image.height && jpeg?.width == image.width && jpeg?.height == image.height && twoWindows && copyClosedEditorOnly
        if pasteboard.changeCount == writtenCount { pasteboard.clearContents(); pasteboard.writeObjects(saved) }
        editor.close(); pin.close()
        let result: [String: Any] = ["fixture_only": true, "annotations": annotationSmoke, "settings_recorder": settingsSmoke, "hotkey_reapply": repeatBindingPassed, "hotkey_fallback_as_primary": fallbackBindingPassed && restoredAfterFallback, "hotkey_conflict_keeps_old_bindings": oldBindingsPreserved, "selection_callback_crop": cropPassed, "resize_event_callback": resizePassed, "escape_restores_drag": cancelGesturePassed, "escape_clears_then_cancels": cancelSequencePassed, "hex_key_clipboard": hexKeyPassed, "rgb_key_clipboard": rgbKeyPassed, "window_click_target": windowClickPassed, "window_drag_is_region": windowDragPassed, "cancel_window_pick": cancelWindowPassed, "png_roundtrip": png?.width == image.width && png?.height == image.height, "jpeg_roundtrip": jpeg?.width == image.width && jpeg?.height == image.height, "two_windows_and_pin_level": twoWindows, "copy_closes_editor_only": copyClosedEditorOnly, "closed_windows_removed": imageWindows.isEmpty, "passed": passed && imageWindows.isEmpty]
        if let path = argument("--smoke-test"), let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path)) }
        exit(passed && imageWindows.isEmpty ? 0 : 1)
    }
    private func runSettingsSmokeTest() -> [String: Bool] {
        let suite = "com.ccshot.settings-tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        var recording: [Bool] = []
        let test = SettingsWindow(preferences: AppPreferences(store: store), applyShortcuts: { capture, _ in
            capture.keyCode == UInt32(kVK_ANSI_J) ? "测试冲突" : nil
        }, recordingChanged: { recording.append($0); return nil })
        var result = test.recordingSmokeTest()
        result["recording_pause_resume_balanced"] = recording == [true, false, true, false, true, false, true, false]
        return result
    }
    private func renderSettings(to path: String) async {
        let suite = "com.ccshot.settings-preview.\(UUID().uuidString)"
        let store = UserDefaults(suiteName:suite)!
        let preview = SettingsWindow(preferences:AppPreferences(store:store),applyShortcuts:{ _, _ in nil },recordingChanged:{ _ in nil })
        preview.present()
        if CommandLine.arguments.contains("--settings-error"), let root = preview.window?.contentView {
            func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
            if let recorder = descendants(root).first(where:{$0 is ShortcutRecorder}) as? ShortcutRecorder {
                recorder.performClick(nil)
                if let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:preview.window!.windowNumber,context:nil,characters:"a",charactersIgnoringModifiers:"a",isARepeat:false,keyCode:0) { recorder.keyDown(with:event) }
            }
        }
        guard CGPreflightScreenCaptureAccess(), let window = preview.window else { exit(2) }
        window.contentView?.layoutSubtreeIfNeeded(); window.display(); CATransaction.flush()
        do {
            let image = try await WindowCapture.capture(id:UInt32(window.windowNumber),ownerPID:ProcessInfo.processInfo.processIdentifier)
            guard let png = ImageWindow.encoded(image,type:.png) else { exit(1) }
            try png.write(to:URL(fileURLWithPath:path),options:.atomic)
        } catch { exit(1) }
        preview.close(); store.removePersistentDomain(forName:suite); exit(0)
    }
    private func renderSelection(_ image: CGImage, to path: String, windowHighlight: Bool = false) {
        guard let context = CGContext(data: nil, width: 1000, height: 650, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.92, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 650))
        context.draw(image, in: CGRect(x: 40, y: 220, width: 920, height: 920 * CGFloat(image.height) / CGFloat(image.width)))
        for row in 0..<10 {
            for column in 0..<10 {
                context.setFillColor((row + column).isMultiple(of: 2) ? NSColor.systemBlue.cgColor : NSColor.systemYellow.cgColor)
                context.fill(CGRect(x: 980 + column * 2, y: 630 + row * 2, width: 2, height: 2))
            }
        }
        guard let composed = context.makeImage() else { exit(1) }
        let view = SelectionView(image: composed, frame: NSRect(x: 0, y: 0, width: 1000, height: 650))
        let window = SelectionWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        if windowHighlight {
            view.windowTargets = [WindowTarget(id: 42, ownerPID: 10, rect: CGRect(x: 40, y: 210, width: 920, height: 250))]
            view.updatePointer(CGPoint(x: 200, y: 350))
        } else {
            view.selectRegion(CGRect(x: 40, y: 210, width: 920, height: 250))
            view.updatePointer(CGPoint(x: 992, y: 642))
        }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: path), options: .atomic); exit(0) }
        catch { exit(1) }
    }
    private func runWindowCaptureTest(_ image: CGImage, report: String) {
        func finish(_ result: [String: Any], code: Int32) {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: report), options: .atomic) }
            exit(code)
        }
        guard CGPreflightScreenCaptureAccess() else {
            finish(["fixture_only": true, "status": "skipped", "reason": "existing_authorization_missing", "passed": false], code: 2)
            return
        }
        let editor = showImage(image, pinned: false)
        let disposable = showImage(image, pinned: true)
        let targetID = UInt32(editor.window!.windowNumber)
        let closedID = UInt32(disposable.window!.windowNumber)
        disposable.close()
        Task { @MainActor in
            do {
                let snapshot = try await WindowCapture.captureSnapshot(id: targetID, ownerPID: ProcessInfo.processInfo.processIdentifier)
                let captured=snapshot.image
                guard let sourceWindow=editor.window,let screen=sourceWindow.screen,let primaryTop=NSScreen.screens.first?.frame.maxY,
                      let region=WindowTarget.editorRect(quartzFrame:snapshot.quartzFrame,screenFrame:screen.frame,primaryTop:primaryTop) else {throw WindowCapture.CaptureError.missing}
                let context=ScreenshotPresentation(background:Self.fixtureBackground(image,on:screen),screenFrame:screen.frame,region:region,displayID:0,allowsAdjustment:false)
                let inline=showDocument(AnnotationDocument(image:captured),pinned:false,screenshot:context)
                let inlineChecks=inline.windowCaptureLayoutChecks(region:region,pixels:CGSize(width:captured.width,height:captured.height))
                inline.close()
                guard let png = ImageWindow.encoded(captured, type: .png) else { throw WindowCapture.CaptureError.unsupportedSize }
                let output = URL(fileURLWithPath: report).deletingPathExtension().appendingPathExtension("png")
                try png.write(to: output, options: .atomic)
                var rejectedClosed = false
                do { _ = try await WindowCapture.capture(id: closedID, ownerPID: ProcessInfo.processInfo.processIdentifier) }
                catch { rejectedClosed = true }
                var rejectedOwner = false
                do { _ = try await WindowCapture.capture(id: targetID, ownerPID: -1) }
                catch { rejectedOwner = true }
                editor.close()
                let passed=rejectedClosed && rejectedOwner && inlineChecks.values.allSatisfy{$0} && !inlineChecks.isEmpty
                finish(["fixture_only":true,"actual_system_window_capture":true,"source_owner_only":true,"width":captured.width,"height":captured.height,"closed_window_rejected":rejectedClosed,"wrong_owner_rejected":rejectedOwner,"inline_checks":inlineChecks,"passed":passed],code:passed ? 0 : 1)
            } catch {
                editor.close()
                finish(["fixture_only": true, "passed": false, "status": "capture_failed"], code: 1)
            }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        cancelCapture()
        for controller in Array(imageWindows.values) { controller.close() }
        settings?.close()
        if let suite=verificationPreferencesSuite {UserDefaults.standard.removePersistentDomain(forName:suite)}
        hotkeys.shutdown()
        NotificationCenter.default.removeObserver(self)
    }
}

@main struct CcShot {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
