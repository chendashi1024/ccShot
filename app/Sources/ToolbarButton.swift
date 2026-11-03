import AppKit

@MainActor final class ToolbarButton:NSButton {
    var primary=false
    var compact=false
    override var intrinsicContentSize:NSSize {
        let font=self.font ?? .systemFont(ofSize:14)
        let text=(title as NSString).size(withAttributes:[.font:font]).width
        let width=title.isEmpty ? (compact ? 44 : 28) : ceil(text)+(image==nil ? 0 : 20)+16
        return NSSize(width:width,height:compact ? 30 : 40)
    }
    func refreshAppearance() {
        isBordered=false;wantsLayer=true;layer?.cornerRadius=7
        let selected=state == .on
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let ink:NSColor=primary ? .white : selected ? (dark ? NSColor(srgbRed:0.68,green:0.86,blue:0.78,alpha:1) : CoreAppearance.accent) : .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let background=primary ? CoreAppearance.accent : selected ? (dark ? NSColor(srgbRed:0.19,green:0.29,blue:0.25,alpha:1) : NSColor(srgbRed:0.90,green:0.94,blue:0.92,alpha:1)) : NSColor.clear
            layer?.backgroundColor=background.cgColor
        }
        attributedTitle=NSAttributedString(string:title,attributes:[.font:font ?? .systemFont(ofSize:14),.foregroundColor:ink])
        contentTintColor=ink;imagePosition=title.isEmpty ? .imageOnly : .imageLeading
        invalidateIntrinsicContentSize();needsDisplay=true
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();refreshAppearance()}
}
