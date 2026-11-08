import AppKit
import Carbon

struct AppShortcut: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String
    static let capture = AppShortcut(keyCode: UInt32(kVK_F1), modifiers: 0, keyName: "F1")
    static let pin = AppShortcut(keyCode: UInt32(kVK_F3), modifiers: 0, keyName: "F3")
    static let fallback = AppShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), keyName: "S")
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers }
    func hash(into hasher: inout Hasher) { hasher.combine(keyCode); hasher.combine(modifiers) }
    static let functionCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    var isFunctionKey: Bool { Self.functionCodes.contains(Int(keyCode)) }
    var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        guard keyCode <= 127, modifiers & ~allowed == 0, !keyName.isEmpty, keyName.utf8.count <= 16,
              !keyName.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        guard isFunctionKey || modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { return false }
        if modifiers & UInt32(cmdKey | shiftKey) == UInt32(cmdKey | shiftKey), [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(Int(keyCode)) { return false }
        if modifiers & UInt32(cmdKey) != 0, [kVK_ANSI_Q, kVK_ANSI_W, kVK_Tab, kVK_Space].contains(Int(keyCode)) { return false }
        return true
    }
    var displayName: String {
        var symbols = ""
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(flag) != 0 { symbols += symbol }
        }
        return symbols + keyName
    }
    static func from(_ event: NSEvent) -> AppShortcut? {
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let name: String
        if let index = functionCodes.firstIndex(of: Int(event.keyCode)) { name = "F\(index + 1)" }
        else { name = event.charactersIgnoringModifiers?.uppercased() ?? "" }
        let shortcut = AppShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: name)
        return shortcut.isValid ? shortcut : nil
    }
}

final class AppPreferences {
    static let shared = AppPreferences()
    let store: UserDefaults
    static let captureKey = "ccshot.capture.shortcut.v1"
    static let pinKey = "ccshot.pin.shortcut.v1"
    static let directoryKey = "ccshot.save.directory.v1"
    init(store: UserDefaults = .standard) { self.store = store }
    private func shortcut(_ key: String, fallback: AppShortcut) -> AppShortcut {
        guard let data = store.data(forKey: key), let value = try? JSONDecoder().decode(AppShortcut.self, from: data), value.isValid else { return fallback }
        return value
    }
    var captureShortcut: AppShortcut { shortcut(Self.captureKey, fallback: .capture) }
    var pinShortcut: AppShortcut { shortcut(Self.pinKey, fallback: .pin) }
    var hasInvalidShortcuts: Bool {
        for key in [Self.captureKey, Self.pinKey] where store.object(forKey: key) != nil {
            guard let data = store.data(forKey: key), let value = try? JSONDecoder().decode(AppShortcut.self, from: data), value.isValid else { return true }
        }
        return false
    }
    func setShortcuts(capture: AppShortcut, pin: AppShortcut) {
        guard capture.isValid, pin.isValid, capture != pin, pin != .fallback else { return }
        store.set(try? JSONEncoder().encode(capture), forKey: Self.captureKey)
        store.set(try? JSONEncoder().encode(pin), forKey: Self.pinKey)
    }
    static var defaultSaveDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true) }
    var saveDirectory: URL? {
        guard let path = store.string(forKey: Self.directoryKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    var usableSaveDirectory: URL? {
        guard let url = saveDirectory else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue, FileManager.default.isWritableFile(atPath: url.path) else { return nil }
        return url
    }
    func setSaveDirectory(_ url: URL?) {
        if let url, url.isFileURL { store.set(url.path, forKey: Self.directoryKey) }
        else { store.removeObject(forKey: Self.directoryKey) }
    }
}
