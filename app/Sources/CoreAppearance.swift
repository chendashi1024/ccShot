import AppKit

enum CoreAppearance {
    static let accent = NSColor(name:"CcShotAccent") { _ in NSColor(srgbRed:0.11,green:0.39,blue:0.35,alpha:1) }
    static let error = NSColor(name:"CcShotError") { appearance in appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(srgbRed:1,green:0.54,blue:0.5,alpha:1) : NSColor(srgbRed:0.7,green:0.15,blue:0.12,alpha:1) }
    static let surface = NSColor(name:"CcShotSurface") { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(srgbRed:0.13,green:0.145,blue:0.14,alpha:1) : NSColor(srgbRed:0.98,green:0.97,blue:0.95,alpha:1)
    }
}
@MainActor final class CoreSurfaceView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { CoreAppearance.surface.setFill(); dirtyRect.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
