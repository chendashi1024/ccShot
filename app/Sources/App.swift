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
    private var hotkeyWarning: NSMenuItem?
    private var captureTask: Task<Void, Never>?
    private var fixture: CGImage?
    private var captureGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let appearance = argument("--appearance") { NSApp.appearance = NSAppearance(named:appearance == "light" ? .aqua : .darkAqua) }
        let menu = NSMenu()
        for (title, action, key) in [("区域截图", #selector(capture), ""), ("钉住剪贴板", #selector(pinClipboard), ""), ("设置…", #selector(openSettings), ","), ("退出 CcShot", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "CcShot"
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
            if let path = argument("--screen-smoke-test") { Task { @MainActor in exit(await ScreenVerification.run(image,reportPath:path)) } }
            else if let path = argument("--fixture-save-directory") {
                let store = UserDefaults(suiteName:"com.ccshot.save-check.\(UUID().uuidString)")!
                store.setVolatileDomain([AppPreferences.directoryKey:path],forName:UserDefaults.argumentDomain)
                showDocument(AnnotationDocument(image:image),pinned:false,preferences:AppPreferences(store:store))
            }
            else if let path = argument("--text-smoke-test") { Task { @MainActor in exit(await TextVerification.run(reportPath:path, previewPath:argument("--text-preview")) ? 0 : 1) } }
            else if let path = argument("--privacy-smoke-test") { Task { @MainActor in exit(await PrivacyVerification.run(reportPath:path, previewPath:argument("--privacy-preview")) ? 0 : 1) } }
            else if let report = argument("--window-smoke-test") { runWindowCaptureTest(image, report: report) }
            else if let path = argument("--render-annotations") { Task { @MainActor in exit(await ImageWindow.annotationPreview(image, to: path) ? 0 : 1) } }
            else if let path = argument("--render-settings") { Task { @MainActor in await renderSettings(to:path) } }
            else if let previewPath = argument("--render-window-highlight") { renderSelection(image, to: previewPath, windowHighlight: true) }
            else if let previewPath = argument("--render-selection") { renderSelection(image, to: previewPath) }
            else if argument("--smoke-test") != nil { runSmokeTest(image) }
            else if CommandLine.arguments.contains("--select") { capture() }
            else { showImage(image, pinned: false) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
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
                guard let window = self?.selectionWindow else { return }
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
        if let fixture { presentSelection(fixture, on: screen); return }
        guard CGPreflightScreenCaptureAccess() else {
            showError("需要屏幕录制权限", detail: "请在系统设置的隐私与安全性中允许 CcShot 屏幕录制，再重新打开应用。")
            return
        }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = number.uint32Value
        let token = captureGeneration
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !Task.isCancelled, token == captureGeneration,
                      let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = CGDisplayPixelsWide(displayID); config.height = CGDisplayPixelsHigh(displayID)
                config.showsCursor = false
                let targets = WindowCapture.targets(in: content, screen: screen)
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard !Task.isCancelled, token == captureGeneration,
                      NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { return }
                presentSelection(image, on: screen, targets: targets)
            } catch {
                guard !Task.isCancelled, token == captureGeneration else { return }
                showError("无法截取屏幕", detail: "请检查屏幕录制权限后重试。")
            }
        }
    }
    private func presentSelection(_ image: CGImage, on screen: NSScreen, targets: [WindowTarget] = []) {
        let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "CcShot · 框选"
        window.level = .screenSaver
        window.isOpaque = true
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SelectionView(image: image, frame: CGRect(origin: .zero, size: screen.frame.size))
        view.windowTargets = targets
        view.onWindowPick = { [weak self, weak view] target in
            guard let self, let view else { return }
            view.showWindowStatus("正在捕获窗口…")
            self.captureTask?.cancel()
            let token = self.captureGeneration
            self.captureTask = Task { @MainActor [weak self, weak view] in
                guard let self else { return }
                do {
                    let captured = try await WindowCapture.capture(id: target.id, ownerPID: target.ownerPID)
                    guard !Task.isCancelled, token == self.captureGeneration else { return }
                    self.cancelCapture()
                    self.showImage(captured, pinned: false)
                } catch {
                    guard !Task.isCancelled, token == self.captureGeneration else { return }
                    view?.showWindowStatus("窗口已关闭或无法捕获，请重新选择或拖动截图区域")
                }
            }
        }
        view.onConfirm = { [weak self] image, _, action in
            guard let self else { return }
            self.cancelCapture()
            switch action {
            case .edit: self.showImage(image, pinned: false)
            case .pin: self.showImage(image, pinned: true)
            case .save: self.showImage(image, pinned: false).saveImage()
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
        view.onCancel = { [weak self] in self?.cancelCapture() }
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
        if hadSelection { showError("屏幕已变化", detail: "请重新开始截图。") }
    }
    @discardableResult private func showImage(_ image: CGImage, pinned: Bool) -> ImageWindow {
        return showDocument(AnnotationDocument(image: image), pinned: pinned)
    }
    @discardableResult private func showDocument(_ document: AnnotationDocument, pinned: Bool, preferences: AppPreferences = .shared) -> ImageWindow {
        let id = UUID()
        let controller = ImageWindow(annotationDocument: document, pinned: pinned, preferences:preferences)
        controller.onClose = { [weak self] in self?.imageWindows.removeValue(forKey: id) }
        controller.onPin = { [weak self] document in self?.showDocument(document, pinned: true) }
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
                let captured = try await WindowCapture.capture(id: targetID, ownerPID: ProcessInfo.processInfo.processIdentifier)
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
                finish(["fixture_only": true, "source_owner_only": true, "width": captured.width, "height": captured.height, "closed_window_rejected": rejectedClosed, "wrong_owner_rejected": rejectedOwner, "passed": rejectedClosed && rejectedOwner], code: rejectedClosed && rejectedOwner ? 0 : 1)
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
