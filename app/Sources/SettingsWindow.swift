import AppKit
import ServiceManagement
import Carbon

@MainActor final class ShortcutRecorder: NSButton {
    var shortcut: AppShortcut { didSet { if !recording { title = shortcut.displayName } } }
    private(set) var recording = false
    var onChange: ((AppShortcut) -> String?)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    init(_ shortcut: AppShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = shortcut.displayName; bezelStyle = .rounded
        target = self; action = #selector(start)
        widthAnchor.constraint(equalToConstant: 160).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    @objc private func start() {
        guard !recording else { return }
        recording = true; title = "按快捷键（Esc 取消）"
        onRecordingChanged?(true)
        window?.makeFirstResponder(self)
    }
    func stop() {
        guard recording else { return }
        recording = false; title = shortcut.displayName; onRecordingChanged?(false)
    }
    override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stop(); return }
        guard let candidate = AppShortcut.from(event) else { onFailure?("请使用组合键或功能键，避开系统截图和常用系统快捷键"); return }
        let error = onChange?(candidate)
        if error == nil { shortcut = candidate }
        stop()
        if let error { onFailure?(error) }
    }
}

@MainActor final class SettingsPanel: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorder, recorder.recording { recorder.keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let preferences: AppPreferences
    private let captureRecorder: ShortcutRecorder
    private let pinRecorder: ShortcutRecorder
    private let directory = NSTextField(labelWithString: "")
    private let permission = NSTextField(labelWithString: "")
    private let login = NSButton(checkboxWithTitle: "登录时启动 ccShort", target: nil, action: nil)
    private let loginStatus = NSTextField(labelWithString: "")
    private let loginSettings = NSButton(title: "打开登录项设置", target: nil, action: nil)
    private let error = NSTextField(wrappingLabelWithString: "")
    private let functionHint = NSTextField(labelWithString: "功能键可配合 Fn 使用，或在系统中启用标准功能键")
    private let fallbackHint = NSTextField(labelWithString: "备选 ⌃⌥S")
    var onClose: (() -> Void)?
    private let applyShortcuts: (AppShortcut, AppShortcut) -> String?
    private let recordingChanged: (Bool) -> String?

    init(preferences: AppPreferences, applyShortcuts: @escaping (AppShortcut, AppShortcut) -> String?, recordingChanged: @escaping (Bool) -> String?) {
        self.preferences = preferences
        self.applyShortcuts = applyShortcuts
        self.recordingChanged = recordingChanged
        captureRecorder = ShortcutRecorder(preferences.captureShortcut)
        pinRecorder = ShortcutRecorder(preferences.pinShortcut)
        let panel = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "ccShort · 设置"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        let root = CoreSurfaceView(); panel.contentView = root
        panel.backgroundColor = CoreAppearance.surface
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)])
        stack.addArrangedSubview(row("截图快捷键", [captureRecorder, button("恢复默认", #selector(resetShortcuts)), fallbackHint]))
        stack.addArrangedSubview(functionHint)
        directory.lineBreakMode = .byTruncatingMiddle; directory.widthAnchor.constraint(equalToConstant: 270).isActive = true
        stack.addArrangedSubview(row("保存位置", [directory, button("更改…", #selector(chooseDirectory)), button("使用默认位置", #selector(clearDirectory))]))
        login.target = self; login.action = #selector(changeLogin)
        loginSettings.target = self; loginSettings.action = #selector(openLoginSettings)
        error.isHidden = true; error.textColor = CoreAppearance.error; error.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(error)
        error.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        captureRecorder.onChange = { [weak self] choice in self?.changeShortcuts(capture: choice, pin: self?.preferences.pinShortcut ?? .pin) }
        pinRecorder.onChange = { [weak self] choice in self?.changeShortcuts(capture: self?.preferences.captureShortcut ?? .capture, pin: choice) }
        for recorder in [captureRecorder, pinRecorder] {
            recorder.onRecordingChanged = { [weak self] recording in
                guard let self else { return }
                if let message = self.recordingChanged(recording) { self.showError(message) }
            }
            recorder.onFailure = { [weak self] message in self?.showError(message) }
        }
        refresh()
        panel.center()
    }
    required init?(coder: NSCoder) { nil }
    private func showError(_ message: String) { error.stringValue = message; error.isHidden = message.isEmpty }
    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: 13); return field
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; return button
    }
    private func row(_ title: String, _ controls: [NSView]) -> NSStackView {
        let heading = label(title); heading.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let row = NSStackView(views: [heading] + controls); row.spacing = 14; row.alignment = .centerY; return row
    }
    func present() { refresh(); showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    private func changeShortcuts(capture: AppShortcut, pin: AppShortcut) -> String? {
        if let message = applyShortcuts(capture, pin) { return message }
        preferences.setShortcuts(capture: capture, pin: pin)
        captureRecorder.shortcut = capture; pinRecorder.shortcut = pin
        showError("")
        refreshHints()
        return nil
    }
    @objc private func resetShortcuts() { if let message = changeShortcuts(capture: .capture, pin: preferences.pinShortcut) { showError(message) } }
    private func refresh() {
        captureRecorder.shortcut = preferences.captureShortcut; pinRecorder.shortcut = preferences.pinShortcut
        if let url = preferences.saveDirectory { directory.stringValue = url.path; directory.toolTip = url.path }
        else { directory.stringValue = "每次保存时选择"; directory.toolTip = nil }
        permission.stringValue = CGPreflightScreenCaptureAccess() ? "已授权" : "未授权，允许后重新打开应用"
        refreshHints()
        if preferences.hasInvalidShortcuts { showError("快捷键设置损坏，当前使用默认值") }
        else if preferences.saveDirectory != nil && preferences.usableSaveDirectory == nil { showError("保存位置不可用，请重新选择") }
    }
    private func refreshHints() {
        functionHint.isHidden = !preferences.captureShortcut.isFunctionKey
        fallbackHint.isHidden = preferences.captureShortcut == .fallback
    }
    private func refreshLogin() {
        let status = SMAppService.mainApp.status
        login.state = status == .enabled || status == .requiresApproval ? .on : .off
        switch status {
        case .enabled: loginStatus.stringValue = "已开启"
        case .requiresApproval: loginStatus.stringValue = "等待系统批准"
        case .notRegistered: loginStatus.stringValue = ""
        case .notFound: loginStatus.stringValue = "开机启动暂不可用"
        @unknown default: loginStatus.stringValue = "无法确认状态"
        }
        loginSettings.isHidden = status != .requiresApproval
    }
    @objc private func changeLogin() {
        let enabled = login.state == .on
        login.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
                showError("")
            } catch { self.showError("未能更改开机启动，请检查系统登录项设置") }
            login.isEnabled = true; refreshLogin()
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") { NSWorkspace.shared.open(url) }
    }
    @objc private func chooseDirectory() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = preferences.usableSaveDirectory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            preferences.setSaveDirectory(url); showError(""); refresh()
        }
    }
    @objc private func clearDirectory() { preferences.setSaveDirectory(nil); showError(""); refresh() }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func windowWillClose(_ notification: Notification) { captureRecorder.stop(); pinRecorder.stop(); onClose?() }
    func recordingSmokeTest() -> [String: Bool] {
        func key(_ code: Int, _ text: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: UInt16(code))!
        }
        captureRecorder.performClick(nil)
        let panel = window as! SettingsPanel
        _ = panel.performKeyEquivalent(with: key(kVK_ANSI_K, "k", [.control, .option]))
        let accepted = !captureRecorder.recording && preferences.captureShortcut.keyCode == UInt32(kVK_ANSI_K)
        let previous = preferences.captureShortcut
        captureRecorder.performClick(nil)
        _ = panel.performKeyEquivalent(with: key(kVK_ANSI_J, "j", [.control, .option]))
        let rejected = !captureRecorder.recording && preferences.captureShortcut == previous
        pinRecorder.performClick(nil)
        pinRecorder.keyDown(with: key(kVK_Escape, "\u{1b}"))
        let canceled = !pinRecorder.recording && preferences.pinShortcut == .pin
        captureRecorder.performClick(nil)
        window?.close()
        return ["recording_accepts_key": accepted, "failed_change_keeps_value": rejected, "escape_stops_recording": canceled, "close_stops_recording": !captureRecorder.recording]
    }
}
