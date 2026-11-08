import AppKit

@MainActor final class ToolbarButton: NSButton {
    var primary = false
    var compact = false
    var minimumTitle = ""
    private let sidePadding: CGFloat = 11
    private let iconGap: CGFloat = 7

    private var titleFont: NSFont { font ?? .systemFont(ofSize: 14) }
    private var titleSize: CGSize { measuredTitle(title) }
    private var iconSize: CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let maxWidth: CGFloat = compact ? 44 : 17
        let maxHeight: CGFloat = compact ? 24 : 17
        let scale = min(1, maxWidth / image.size.width, maxHeight / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func measuredTitle(_ text: String) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let size = (text as NSString).size(withAttributes: [.font: titleFont])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = max(titleSize.width, measuredTitle(minimumTitle).width)
        let iconWidth = iconSize.width
        let gap = textWidth > 0 && iconWidth > 0 ? iconGap : 0
        let width = textWidth > 0 ? textWidth + iconWidth + gap + 2 * sidePadding : (compact ? 44 : 34)
        return NSSize(width: ceil(width), height: compact ? 30 : 40)
    }

    func contentFrames(in bounds: CGRect) -> (icon: CGRect, title: CGRect) {
        let icon = iconSize, text = titleSize
        let gap = icon.width > 0 && text.width > 0 ? iconGap : 0
        let x = bounds.midX - (icon.width + gap + text.width) / 2
        return (CGRect(x: x, y: bounds.midY - icon.height / 2, width: icon.width, height: icon.height),
                CGRect(x: x + icon.width + gap, y: bounds.midY - text.height / 2, width: text.width, height: text.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        if compact {
            super.draw(dirtyRect)
            return
        }
        let frames = contentFrames(in: bounds)
        let ink = contentTintColor ?? .labelColor
        let opacity: CGFloat = isEnabled ? 1 : 0.42
        if isEnabled && isHighlighted {
            ink.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        if let image, !frames.icon.isEmpty, let context = NSGraphicsContext.current?.cgContext {
            // 模板图标单独着色，避免修改按钮底色和透明区域。
            context.saveGState()
            context.clip(to: frames.icon)
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            image.draw(in: frames.icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            ink.setFill()
            frames.icon.fill(using: .sourceAtop)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        if !frames.title.isEmpty {
            (title as NSString).draw(in: frames.title, withAttributes: [.font: titleFont, .foregroundColor: ink.withAlphaComponent(opacity)])
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }

    func refreshAppearance() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 7
        let selected = state == .on
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selectionInk = dark ? NSColor(srgbRed: 0.68, green: 0.86, blue: 0.78, alpha: 1) : CoreAppearance.accent
        contentTintColor = primary ? .white : selected ? selectionInk : .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let selectionBackground = dark ? NSColor(srgbRed: 0.19, green: 0.29, blue: 0.25, alpha: 1) : NSColor(srgbRed: 0.90, green: 0.94, blue: 0.92, alpha: 1)
            layer?.backgroundColor = (primary ? CoreAppearance.accent : selected ? selectionBackground : .clear).cgColor
        }
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}
