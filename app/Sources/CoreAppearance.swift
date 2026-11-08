import AppKit

enum CoreAppearance {
    static let accent = NSColor(name:"CcShotAccent") { _ in NSColor(srgbRed:0.11,green:0.39,blue:0.35,alpha:1) }
    static let captureBorderWidth: CGFloat = 2
    static func captureOutline(_ rect: CGRect) -> CGPath {
        let radius = min(6, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    static let captureBorder = NSColor(name: "CcShotCaptureBorder") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.40, green: 0.67, blue: 0.60, alpha: 1)
            : NSColor(srgbRed: 0.29, green: 0.54, blue: 0.45, alpha: 1)
    }
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

// 面板变窄时滚动内容，保留按钮的原始宽度和外侧留白。
@MainActor final class FloatingControls: NSView {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    let stack: NSStackView
    private let scroll = NSScrollView()

    init(rows: [NSView], primaryToolbar: Bool = false) {
        horizontalPadding = primaryToolbar ? 14 : 16
        verticalPadding = primaryToolbar ? 6 : 10
        stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .legacy
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = stack
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { nil }

    func panelSize(maxWidth: CGFloat) -> CGSize {
        let natural = stack.fittingSize
        let width = natural.width + 2 * horizontalPadding
        let scrollbar = width > maxWidth ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        return CGSize(width: min(width, maxWidth), height: natural.height + 2 * verticalPadding + scrollbar)
    }
    func place(in bounds: CGRect) {
        frame = bounds
        fitContent()
    }
    func fitContent() {
        let natural = stack.fittingSize
        scroll.frame = bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
        scroll.hasHorizontalScroller = natural.width > scroll.frame.width
        stack.setFrameSize(natural)
        stack.layoutSubtreeIfNeeded()
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
