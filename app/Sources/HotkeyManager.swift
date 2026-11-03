import AppKit
import Carbon

@MainActor final class HotkeyManager {
    enum Action { case capture, pin }
    var onAction: ((Action) -> Void)?
    private struct Binding { let reference: EventHotKeyRef; let id: UInt32 }
    private var bindings: [AppShortcut: Binding] = [:]
    private var actions: [UInt32: Action] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private(set) var lastError: String?
    var activeCount: Int { bindings.count }

    func apply(capture: AppShortcut, pin: AppShortcut) -> String? {
        guard capture.isValid, pin.isValid else { return fail("请选择带修饰键的组合键或功能键") }
        guard capture != pin, pin != .fallback else { return fail("截图与钉图快捷键不能相同，也不能占用备选截图键") }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                      identifier.signature == 0x43435348 else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
                let id = identifier.id
                Task { @MainActor in if let action = manager.actions[id] { manager.onAction?(action) } }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return fail("无法启用全局快捷键，可先从菜单栏截图") }
        }
        var desired: [AppShortcut: Action] = [capture: .capture, pin: .pin]
        desired[.fallback] = .capture
        var pending: [AppShortcut: Binding] = [:]
        for shortcut in desired.keys where bindings[shortcut] == nil {
            var reference: EventHotKeyRef?
            let id = nextID; nextID &+= 1
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43435348, id: id), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                for binding in pending.values { UnregisterEventHotKey(binding.reference) }
                return fail("快捷键可能已被占用，请换一个组合键")
            }
            pending[shortcut] = Binding(reference: reference, id: id)
        }
        // 新注册全部成功后才释放不再使用的旧键，失败时保留原绑定。
        for (shortcut, binding) in bindings where desired[shortcut] == nil { UnregisterEventHotKey(binding.reference) }
        var updated: [AppShortcut: Binding] = [:]
        var updatedActions: [UInt32: Action] = [:]
        for (shortcut, action) in desired {
            if let binding = bindings[shortcut] ?? pending[shortcut] { updated[shortcut] = binding; updatedActions[binding.id] = action }
        }
        bindings = updated; actions = updatedActions; lastError = nil
        return nil
    }
    private func fail(_ message: String) -> String { lastError = message; return message }
    func pause() {
        for binding in bindings.values { UnregisterEventHotKey(binding.reference) }
        bindings.removeAll(); actions.removeAll()
    }
    func shutdown() {
        pause()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
