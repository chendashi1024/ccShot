import AppKit

struct ScreenshotPresentation {
    let background: CGImage
    let screenFrame: CGRect
    let region: CGRect
    let displayID: UInt32
    let allowsAdjustment: Bool
    var captureSize: CGSize {screenFrame.size}
    func replacingRegion(_ value: CGRect) -> Self {
        Self(background:background,screenFrame:screenFrame,region:value,displayID:displayID,allowsAdjustment:allowsAdjustment)
    }
}

@MainActor final class ScreenshotStatus: NSTextField {
    var onChange:(()->Void)?
    override var stringValue:String {didSet {onChange?()}}
}

@MainActor final class ScreenshotView: NSView {
    let presentation: ScreenshotPresentation
    var region: CGRect
    var placement: ScreenshotPlacement?
    var canAdjust = true {didSet {border.needsDisplay=true}}
    var sourceGeometryAvailable = true
    var imagePixels: CGSize
    weak var imageView: NSView?
    var chrome:[NSView] = []
    var onLayout:(()->Void)?
    var onAdjustmentBegin:(()->Void)?
    var onAdjustmentCancel:(()->Void)?
    var onRegionChange:((CGRect)->Bool)?
    private(set) var isAdjusting=false
    private let border=ScreenshotBorder()
    private var anchor:CGPoint?
    private var previous:CGRect = .zero
    private var handle:SelectionHandle?
    private var moving=false

    init(presentation:ScreenshotPresentation,imagePixels:CGSize) {
        self.presentation=presentation;region=presentation.region;self.imagePixels=imagePixels
        super.init(frame:CGRect(origin:.zero,size:presentation.captureSize))
        border.autoresizingMask=[.width,.height]
    }
    required init?(coder:NSCoder) {nil}
    override var isOpaque:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    func installBorder() {addSubview(border)}
    override func layout() {super.layout();onLayout?();refreshBorder()}
    func refreshBorder() {
        border.frame=bounds;border.selection=placement?.image ?? .zero
        border.toolbar = isAdjusting ? nil : placement?.toolbar
        border.handles=canAdjust && !isAdjusting
        border.pixels=isAdjusting ? CGSize(width:region.width / presentation.captureSize.width*CGFloat(presentation.background.width),height:region.height / presentation.captureSize.height*CGFloat(presentation.background.height)) : imagePixels
        border.needsDisplay=true;needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let c=NSGraphicsContext.current?.cgContext,let placement else {return}
        NSColor.black.setFill();bounds.fill()
        c.draw(presentation.background,in:placement.background)
        c.saveGState();let p=CGMutablePath();p.addRect(bounds);p.addRect(placement.image);c.addPath(p)
        c.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor);c.drawPath(using:.eoFill);c.restoreGState()
    }
    private func capturePoint(_ point:CGPoint)->CGPoint? {
        guard let background=placement?.background,background.width>0 else {return nil}
        return CGPoint(x:min(presentation.captureSize.width,max(0,(point.x-background.minX)/background.width*presentation.captureSize.width)),y:min(presentation.captureSize.height,max(0,(point.y-background.minY)/background.height*presentation.captureSize.height)))
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        let local=convert(point,from:superview)
        guard bounds.contains(local) else {return nil}
        if chrome.contains(where:{!$0.isHidden && $0.frame.contains(local)}) {return super.hitTest(point)}
        if canAdjust,let rect=placement?.image {
            let near=rect.insetBy(dx:-7,dy:-7).contains(local)
            let inside=rect.width>14 && rect.height>14 && rect.insetBy(dx:7,dy:7).contains(local)
            if near && !inside {return self}
            if !rect.contains(local) {return self}
        }
        return super.hitTest(point)
    }
    override func mouseDown(with event:NSEvent) {
        guard canAdjust,sourceGeometryAvailable,let point=capturePoint(convert(event.locationInWindow,from:nil)) else {return}
        window?.makeFirstResponder(self);anchor=point;previous=region
        let scale=(placement?.background.width ?? 1)/presentation.captureSize.width
        let tolerance=7/max(0.001,scale)
        handle=SelectionHandle.allCases.first {let p=$0.point(in:region);return hypot(p.x-point.x,p.y-point.y)<=tolerance}
        moving=handle==nil && region.insetBy(dx:-tolerance,dy:-tolerance).contains(point)
        isAdjusting=true;onAdjustmentBegin?();imageView?.isHidden=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard isAdjusting,let anchor,let point=capturePoint(convert(event.locationInWindow,from:nil)) else {return}
        if let handle {region=handle.resize(previous,toward:point,canvas:presentation.captureSize,minimum:CGSize(width:presentation.captureSize.width/CGFloat(presentation.background.width),height:presentation.captureSize.height/CGFloat(presentation.background.height)))}
        else if moving {
            var rect=previous.offsetBy(dx:point.x-anchor.x,dy:point.y-anchor.y)
            rect.origin.x=min(max(0,rect.minX),presentation.captureSize.width-rect.width);rect.origin.y=min(max(0,rect.minY),presentation.captureSize.height-rect.height);region=rect
        } else {region=CGRect(x:min(anchor.x,point.x),y:min(anchor.y,point.y),width:abs(point.x-anchor.x),height:abs(point.y-anchor.y))}
        // 与真正裁图共用像素边界，避免预览框与最终裁剪相差一列。
        if let pixels=CaptureGeometry.pixelRect(region,canvas:presentation.captureSize,image:CGSize(width:presentation.background.width,height:presentation.background.height)) {region=CaptureGeometry.viewRect(pixels,canvas:presentation.captureSize,image:CGSize(width:presentation.background.width,height:presentation.background.height))}
        onLayout?();refreshBorder()
    }
    override func mouseUp(with event:NSEvent) {
        guard isAdjusting else {return}
        isAdjusting=false;anchor=nil;handle=nil
        guard region.width>0,region.height>0,region != previous else {cancelAdjustment();return}
        if onRegionChange?(region) != true {cancelAdjustment()}
    }
    private func cancelAdjustment() {
        region=previous;isAdjusting=false;anchor=nil;handle=nil;imageView?.isHidden=false
        onAdjustmentCancel?();onLayout?();refreshBorder()
    }
    override func keyDown(with event:NSEvent) {
        if isAdjusting,event.keyCode==53 {cancelAdjustment()} else {super.keyDown(with:event)}
    }
    override func cancelOperation(_ sender:Any?) {if isAdjusting {cancelAdjustment()} else {super.cancelOperation(sender)}}
}

@MainActor private final class ScreenshotBorder:NSView {
    var selection:CGRect = .zero
    var handles=true
    var toolbar: CGRect?
    var pixels:CGSize = .zero
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect:NSRect) {
        guard !selection.isEmpty, let context = NSGraphicsContext.current?.cgContext else {return}
        let outline = CoreAppearance.captureOutline(selection)
        // 圆角只影响画面上的边线和遮罩，导出仍使用原始矩形像素。
        context.addRect(selection)
        context.addPath(outline)
        context.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor)
        context.drawPath(using: .eoFill)
        context.setStrokeColor(CoreAppearance.captureBorder.cgColor)
        context.setLineWidth(CoreAppearance.captureBorderWidth)
        context.addPath(outline)
        context.strokePath()
        if handles {
            for handle in SelectionHandle.allCases {
                let p = handle.point(in: selection)
                let box = NSBezierPath(roundedRect: CGRect(x: p.x-2.5, y: p.y-2.5, width: 5, height: 5), xRadius: 1.5, yRadius: 1.5)
                CoreAppearance.surface.setFill()
                box.fill()
                CoreAppearance.captureBorder.setStroke()
                box.stroke()
            }
        }
        let text="\(Int(pixels.width.rounded())) × \(Int(pixels.height.rounded())) px" as NSString
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.white]
        let size=text.size(withAttributes:attributes)
        let width = size.width + 12, height = size.height + 8
        let maxY = bounds.maxY - height - 8
        var box = CGRect(x: max(8, min(selection.minX, bounds.maxX - width - 8)),
                         y: min(maxY, selection.maxY + 10), width: width, height: height)
        if let toolbar, box.intersects(toolbar) {
            let left = selection.minX - width - 8
            box.origin.x = left >= 8 ? left : box.minX + 8
            box.origin.x = min(box.minX, bounds.maxX - width - 8)
            box.origin.y = max(8, min(maxY, selection.maxY - height - 8))
        }
        NSColor(calibratedWhite:0.12,alpha:0.88).setFill();NSBezierPath(roundedRect:box,xRadius:4,yRadius:4).fill()
        text.draw(at:CGPoint(x:box.minX+6,y:box.minY+4),withAttributes:attributes)
    }
}
