import AppKit

@MainActor final class ScreenshotColorWell:NSColorWell {
    private var previousLevel:NSWindow.Level?
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let hit=super.hitTest(point) else {return nil}
        return window?.level == .screenSaver ? self : hit
    }
    override func mouseDown(with event:NSEvent) {
        guard window?.level == .screenSaver else {super.mouseDown(with:event);return}
        activate(true);NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }
    override func activate(_ exclusive:Bool) {
        super.activate(exclusive)
        guard let window,window.level == .screenSaver else {return}
        let panel=NSColorPanel.shared
        if previousLevel == nil {previousLevel=panel.level}
        panel.level=NSWindow.Level(rawValue:window.level.rawValue+1)
    }
    override func deactivate() {
        super.deactivate()
        if let level=previousLevel {previousLevel=nil;NSColorPanel.shared.level=level}
    }
    func suspend() {
        guard isActive || previousLevel != nil else {return}
        deactivate();NSColorPanel.shared.orderOut(nil)
    }
}
