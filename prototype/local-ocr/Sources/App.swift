import AppKit
import VisionKit
import ScreenCaptureKit
import Carbon

@MainActor final class Controller: NSObject, NSApplicationDelegate, ImageAnalysisOverlayViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let imageView = NSImageView()
    let overlay = ImageAnalysisOverlayView()
    let status = NSTextField(labelWithString: "正在准备本地识别原型…")
    let analyzer = ImageAnalyzer()
    let fixtureURL: URL?
    let evidenceURL: URL?
    let selfTest: Bool
    var hotKeys: [EventHotKeyRef] = []
    var handler: EventHandlerRef?
    var localKeyMonitor: Any?
    var synthetic = false
    var generation = 0
    var readyAt: Double = 0

    init(fixtureURL: URL?, evidenceURL: URL?, selfTest: Bool) {
        self.fixtureURL = fixtureURL
        self.evidenceURL = evidenceURL
        self.selfTest = selfTest
        super.init()
    }

    func event(_ name: String, _ values: [String: Any] = [:]) {
        guard let evidenceURL else { return }
        var row = values
        row["event"] = name
        row["time"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        let line = data + Data([10])
        if !FileManager.default.fileExists(atPath: evidenceURL.path) {
            FileManager.default.createFile(atPath: evidenceURL.path, contents: line)
        } else if let handle = try? FileHandle(forWritingTo: evidenceURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window.title = "ccShot · 本地选字技术原型"
        window.minSize = NSSize(width: 760, height: 450)
        window.center()
        let root = window.contentView!
        let heading = NSTextField(labelWithString: "截图后直接选字  ·  全程本机识别")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let hint = NSTextField(labelWithString: "临时技术界面：⌃⌥S / F1 唤醒 · 拖选图片文字 · ⌘C 复制 · ⌘A 全选")
        hint.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [button("截取当前屏幕", #selector(captureScreen)),
                                         button("载入测试样本", #selector(loadFixture)),
                                         button("验证样本窗口快照", #selector(captureFixtureWindow)),
                                         button("复制选中文字", #selector(copySelection)),
                                         button("复制全部文字", #selector(copyAll))])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        overlay.delegate = self
        overlay.trackingImageView = imageView
        overlay.preferredInteractionTypes = .textSelection
        overlay.autoresizingMask = [.width, .height]
        imageView.addSubview(overlay)
        let stack = NSStackView(views: [heading, hint, buttons, imageView, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "ccShot")
        appItem.submenu?.addItem(withTitle: "退出原型", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: "编辑")
        for (title, action, key) in [("复制", #selector(copySelection), "c"), ("全选", #selector(selectAllText), "a")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            edit.submenu?.addItem(item)
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
        registerHotkeys()
        if fixtureURL != nil && CommandLine.arguments.contains("--diagnose-keys") {
            // 仅显式诊断模式记录三个测试快捷键，不记录普通输入按键。
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] input in
                let flags = input.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if (input.keyCode == UInt16(kVK_ANSI_S) && flags.contains([.control, .option])) ||
                   input.keyCode == UInt16(kVK_F1) ||
                   (input.keyCode == UInt16(kVK_ANSI_A) && flags.contains(.command)) {
                    self?.event("fixture_key_down", ["key_code": input.keyCode, "modifiers": flags.rawValue])
                }
                return input
            }
        }
        event("startup", ["image_analyzer_supported": ImageAnalyzer.isSupported,
                          "screen_capture_authorized": CGPreflightScreenCaptureAccess(),
                          "accessibility_authorized": AXIsProcessTrusted()])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if fixtureURL != nil { loadFixture() }
        else { status.stringValue = "点击截屏；若权限不足，只提示，不申请或修改系统设置。" }
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    func registerHotkeys() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let controller = Unmanaged<Controller>.fromOpaque(userData).takeUnretainedValue()
            let id = identifier.id
            Task { @MainActor in controller.hotkeyPressed(id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        event("hotkey_handler", ["status": result])
        for (id, key, modifiers, name) in [(UInt32(1), UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey), "control-option-S"),
                                           (UInt32(2), UInt32(kVK_F1), UInt32(0), "F1")] {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x43435348, id: id),
                                             GetEventDispatcherTarget(), 0, &reference)
            if let reference { hotKeys.append(reference) }
            event("hotkey_registration", ["shortcut": name, "status": status])
        }
    }

    func hotkeyPressed(_ id: UInt32) {
        readyAt = ProcessInfo.processInfo.systemUptime
        event("hotkey_received", ["id": id, "fixture_mode": fixtureURL != nil])
        if fixtureURL != nil { loadFixture() } else { captureScreen() }
    }

    @objc func loadFixture() {
        guard let fixtureURL else {
            status.stringValue = "请使用带 --fixture 参数的启动命令载入固定测试图片。"
            return
        }
        do { show(try readImage(fixtureURL), synthetic: true) }
        catch { status.stringValue = error.localizedDescription; event("load_error", ["error": error.localizedDescription]) }
    }

    @objc func captureScreen() {
        // 不调用任何权限请求 API；本轮不打开系统设置或重置权限。
        guard CGPreflightScreenCaptureAccess() else {
            status.stringValue = "屏幕录制未授权：本轮不申请权限，可先用测试样本验证选字。"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            event("capture_blocked", ["reason": "screen_recording_permission_not_granted", "prompt_requested": false])
            return
        }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = CGDisplayPixelsWide(displayID)
                config.height = CGDisplayPixelsHigh(displayID)
                config.showsCursor = false
                let start = ProcessInfo.processInfo.systemUptime
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                event("capture_success", ["width": image.width, "height": image.height,
                                          "capture_ms": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                                          "saved_to_disk": false])
                show(image, synthetic: false)
            } catch { status.stringValue = "截屏失败：\(error.localizedDescription)"; event("capture_error", ["error": error.localizedDescription]) }
        }
    }

    @objc func captureFixtureWindow() {
        guard synthetic, fixtureURL != nil else {
            status.stringValue = "先载入固定测试样本；此检查只截原型自己的窗口。"
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            event("fixture_capture_blocked", ["reason": "screen_recording_permission_not_granted", "prompt_requested": false])
            status.stringValue = "屏幕录制未授权，本轮不请求。"
            return
        }
        let windowID = CGWindowID(window.windowNumber)
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let ownWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    event("fixture_capture_error", ["reason": "own_window_not_found"])
                    return
                }
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * (window.screen?.backingScaleFactor ?? 2))
                config.height = Int(window.frame.height * (window.screen?.backingScaleFactor ?? 2))
                config.showsCursor = false
                let start = ProcessInfo.processInfo.systemUptime
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: config)
                event("fixture_capture_success", ["source": "own_synthetic_window_only", "width": image.width,
                       "height": image.height, "capture_ms": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                       "saved_to_disk": false])
                show(image, synthetic: true)
            } catch { event("fixture_capture_error", ["error": error.localizedDescription]) }
        }
    }

    func show(_ image: CGImage, synthetic: Bool) {
        generation += 1
        let token = generation
        self.synthetic = synthetic
        overlay.analysis = nil
        let logicalWidth = min(Double(image.width), 960)
        imageView.image = NSImage(cgImage: image, size: NSSize(width: logicalWidth, height: logicalWidth * Double(image.height) / Double(image.width)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.contentView?.layoutSubtreeIfNeeded()
        overlay.frame = imageView.bounds
        overlay.setContentsRectNeedsUpdate()
        if readyAt > 0 {
            event("snapshot_presented", ["wake_ms": (ProcessInfo.processInfo.systemUptime - readyAt) * 1000, "synthetic": synthetic])
            readyAt = 0
        }
        status.stringValue = "本机识别中…"
        Task { @MainActor in
            let start = ProcessInfo.processInfo.systemUptime
            do {
                let analysis = try await LocalOCR.recognize(image, analyzer: analyzer)
                guard token == generation else { return }
                overlay.analysis = analysis
                overlay.preferredInteractionTypes = .textSelection
                overlay.selectableItemsHighlighted = true
                overlay.setContentsRectNeedsUpdate()
                let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
                status.stringValue = "\(synthetic ? "合成测试样本" : "屏幕快照") · 本机识别 \(Int(ms)) ms · 可直接拖选图片文字"
                event("analysis_ready", ["synthetic": synthetic, "characters": analysis.transcript.count, "latency_ms": ms])
                if selfTest && synthetic { selectionSelfTest() }
            } catch { status.stringValue = "识别失败：\(error.localizedDescription)"; event("analysis_error", ["error": error.localizedDescription]) }
        }
    }

    @objc func selectAllText() {
        let text = overlay.text
        guard !text.isEmpty else { return }
        overlay.selectedRanges = [text.startIndex..<text.endIndex]
    }

    @objc func copySelection() {
        let text = overlay.selectedText
        guard !text.isEmpty else { status.stringValue = "请先在图片上拖选文字。"; return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        event("copy_selection", ["synthetic": synthetic, "characters": text.count,
                                  "synthetic_text": synthetic ? text : "[private screenshot text omitted]",
                                  "clipboard_roundtrip_matches": NSPasteboard.general.string(forType: .string) == text])
        status.stringValue = "已复制 \(text.count) 个字符"
    }

    @objc func copyAll() { selectAllText(); copySelection() }

    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
        event("selection_changed", ["synthetic": synthetic, "characters": overlayView.selectedText.count,
                                    "ranges": overlayView.selectedRanges.count])
    }

    func selectionSelfTest() {
        let text = overlay.text
        guard text.count > 4 else {
            event("selection_selftest", ["passed": false, "reason": "insufficient_text"])
            if CommandLine.arguments.contains("--exit-after-self-test") { exit(1) }
            return
        }
        // 只对虚构样本定位范围设置与文字读取之间的边界差异。
        for (startOffset, count) in [(0, 1), (0, 4), (1, 1), (1, 3), (text.count - 1, 1)] {
            let start = text.index(text.startIndex, offsetBy: startOffset)
            let end = text.index(start, offsetBy: count)
            overlay.selectedRanges = [start..<end]
            let actualRanges = overlay.selectedRanges.map { NSRange($0, in: text) }
            event("range_diagnostic", ["requested_location": startOffset, "requested_count": count,
                  "returned_ranges": actualRanges.map { ["location": $0.location, "length": $0.length] },
                  "expected": String(text[start..<end]), "actual": overlay.selectedText])
            overlay.selectedRanges = [start..<text.index(before: end)]
            event("adjusted_range_probe", ["requested_location": startOffset, "requested_count": count,
                  "expected": String(text[start..<end]), "actual": overlay.selectedText])
        }
        let end = text.index(text.startIndex, offsetBy: 4)
        overlay.selectedRanges = [text.startIndex..<end]
        let expected = String(text[..<end])
        // 保存并恢复原剪贴板，不记录它的内容。
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        copySelection()
        let matches = overlay.selectedText == expected && pasteboard.string(forType: .string) == expected
        let actual = overlay.selectedText
        selectAllText()
        copySelection()
        let fullMatches = overlay.selectedText == text && pasteboard.string(forType: .string) == text
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        event("selection_selftest", ["partial_range_exact": matches, "full_selection_exact": fullMatches,
              "method": "native_selectedRanges_and_pasteboard_roundtrip", "expected_synthetic_text": expected,
              "actual_synthetic_text": actual, "clipboard_restored": true])
        if CommandLine.arguments.contains("--exit-after-self-test") { exit(matches && fullMatches ? 0 : 1) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        for ref in hotKeys { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@main struct Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let app = NSApplication.shared
        if let i = args.firstIndex(of: "--benchmark"), args.count > i + 2 {
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do {
                    try await runBenchmark(fixturesDirectory: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]))
                    exit(0)
                } catch { fputs("\(error)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        func value(_ flag: String) -> String? { guard let i = args.firstIndex(of: flag), args.count > i + 1 else { return nil }; return args[i + 1] }
        let controller = Controller(fixtureURL: value("--fixture").map { URL(fileURLWithPath: $0) },
                                    evidenceURL: value("--evidence").map { URL(fileURLWithPath: $0) },
                                    selfTest: args.contains("--self-test"))
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
