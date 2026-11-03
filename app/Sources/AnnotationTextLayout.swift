import AppKit

@MainActor enum AnnotationTextLayout {
    static let inset: CGFloat = 4
    static func attributes(_ style: AnnotationStyle) -> [NSAttributedString.Key:Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        return [.font:NSFont.systemFont(ofSize:style.fontSize,weight:style.bold ? .bold : .regular),.foregroundColor:style.color.nsColor,.paragraphStyle:paragraph]
    }
    static func size(_ text: String, style: AnnotationStyle, maxWidth: CGFloat) -> CGSize {
        let width = max(1,maxWidth-2*inset)
        let rect = (text as NSString).boundingRect(with:CGSize(width:width,height:1000000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes(style))
        let font = NSFont.systemFont(ofSize:style.fontSize,weight:style.bold ? .bold : .regular)
        let lineHeight = font.ascender-font.descender+font.leading
        return CGSize(width:min(maxWidth,max(2*inset+1,ceil(rect.width+2*inset))),height:ceil(max(lineHeight,rect.height)+(text.hasSuffix("\n") ? lineHeight : 0)+2*inset))
    }
    static func draw(_ object: AnnotationObject, in context: CGContext) {
        let rect = object.bounds
        if object.style.textBackground { context.setFillColor(object.style.backgroundColor.nsColor.cgColor); context.fill(rect) }
        let textRect = rect.insetBy(dx:inset,dy:inset)
        (object.text as NSString).draw(with:textRect,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes(object.style))
    }
}

@MainActor final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) && !hasMarkedText() { onCommit?(); return }
        if event.keyCode == 53 && !hasMarkedText() { onCancel?(); return }
        super.keyDown(with:event)
    }
}
