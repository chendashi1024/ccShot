import AppKit
import Carbon

@main struct PreferencesTests {
    static func main() throws {
        let suite = "com.ccshot.tests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(store: store)
        precondition(prefs.captureShortcut == .capture && prefs.pinShortcut == .pin)
        precondition(!AppShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: 0, keyName: "S").isValid, "不能截获普通输入字母")
        precondition(!AppShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), keyName: "4").isValid, "不得占用系统截图组合键")
        store.set(Data("bad".utf8), forKey: AppPreferences.captureKey)
        precondition(prefs.hasInvalidShortcuts && prefs.captureShortcut == .capture, "损坏设置应回到合法默认")
        prefs.setShortcuts(capture: .fallback, pin: .pin)
        let reopened = AppPreferences(store: UserDefaults(suiteName: suite)!)
        precondition(reopened.captureShortcut == .fallback && !reopened.hasInvalidShortcuts, "配置应可跨实例恢复")
        prefs.setShortcuts(capture: .capture, pin: .fallback)
        precondition(prefs.captureShortcut == .fallback && prefs.pinShortcut == .pin, "拒绝互相冲突的设置，不覆盖旧值")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ccshot-preferences-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        prefs.setSaveDirectory(folder)
        precondition(reopened.usableSaveDirectory?.standardizedFileURL == folder.standardizedFileURL)
        prefs.setSaveDirectory(folder.appendingPathComponent("missing"))
        precondition(reopened.saveDirectory != nil && reopened.usableSaveDirectory == nil, "失效目录不能冒充可写")
        prefs.setSaveDirectory(nil)
        precondition(reopened.saveDirectory == nil)
        print("通过：快捷键校验、损坏回退、持久恢复、保存目录失效")
    }
}
