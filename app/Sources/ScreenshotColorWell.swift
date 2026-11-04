import AppKit

@MainActor final class ScreenshotColorWell:NSColorWell {
    private var previousLevel:NSWindow.Level?
    private var needsRaisedPanel:Bool {window?.level == .screenSaver || window?.parent != nil}
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let hit=super.hitTest(point) else {return nil}
        return needsRaisedPanel ? self : hit
    }
    override func mouseDown(with event:NSEvent) {
        guard needsRaisedPanel else {super.mouseDown(with:event);return}
        activate(true);NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }
    override func activate(_ exclusive:Bool) {
        super.activate(exclusive)
        guard let window,needsRaisedPanel else {return}
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
