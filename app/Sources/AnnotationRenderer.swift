import AppKit
import CoreImage

@MainActor enum AnnotationRenderer {
    static func render(base: CGImage, objects: [AnnotationObject]) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for object in objects { guard draw(object, in: context) else { return nil } }
        return context.makeImage()
    }
    @discardableResult static func draw(_ object: AnnotationObject, in context: CGContext) -> Bool {
        context.saveGState(); defer { context.restoreGState() }
        let style = object.style
        guard style.valid else { return false }
        let opacity = style.filled && [.rectangle,.ellipse].contains(object.tool) ? style.fillOpacity : 1
        let color = style.color.nsColor.withAlphaComponent(style.color.alpha * (object.tool == .highlight ? 0.3 : opacity))
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(style.width); context.setLineCap(.round); context.setLineJoin(.round)
        if style.dashed { context.setLineDash(phase: 0, lengths: [style.width * 3, style.width * 2]) }
        switch object.tool {
        case .rectangle, .ellipse:
            let rect = object.bounds
            let path = object.tool == .ellipse ? CGPath(ellipseIn: rect, transform: nil) : CGPath(roundedRect: rect, cornerWidth: min(style.cornerRadius, rect.width/2), cornerHeight: min(style.cornerRadius, rect.height/2), transform: nil)
            context.addPath(path); context.drawPath(using: style.filled ? .fill : .stroke)
        case .line:
            context.addPath(object.strokePath); context.strokePath()
        case .arrow:
            drawArrow(object, in: context)
        case .pen, .highlight:
            guard let first = object.points.first else { return true }
            context.move(to: first)
            if object.points.count == 1 {
                context.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            } else {
                var previous = first
                for point in object.points.dropFirst() {
                    context.addQuadCurve(to: CGPoint(x: (point.x+previous.x)/2, y: (point.y+previous.y)/2), control: previous)
                    previous = point
                }
                context.addLine(to: previous)
            }
            context.strokePath()
        case .text: AnnotationTextLayout.draw(object,in:context)
        case .mask:
            var processed: CGImage?
            if style.maskEffect != .solid {
                guard let source = context.makeImage(),let image = filtered(source,style:style) else {return false}
                processed=image
            }
            context.setLineDash(phase: 0, lengths: [])
            if style.maskBrush {
                guard let first = object.points.first else { return true }
                context.move(to: first)
                if object.points.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
                else { for point in object.points.dropFirst() { context.addLine(to: point) } }
                context.replacePathWithStrokedPath(); context.clip()
            } else { context.clip(to: style.maskEffect == .solid ? object.bounds.integral : object.bounds) }
            if let processed {context.draw(processed,in:CGRect(x:0,y:0,width:processed.width,height:processed.height))}
            else {
                // 实心遮挡始终不透明，不能继承旧样式或颜色面板中的Alpha。
                context.setFillColor(style.color.nsColor.withAlphaComponent(1).cgColor)
                context.fill(context.boundingBoxOfClipPath)
            }
        case .number:
            let rect = object.bounds
            context.fillEllipse(in: rect)
            let font = NSFont.systemFont(ofSize: min(rect.height * 0.6, rect.width / CGFloat(max(1, String(object.number).count)) * 1.1), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let text = String(object.number) as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: rect.midX-size.width/2, y: rect.midY-size.height/2), withAttributes: attributes)
        case .select: break
        }
        return true
    }
    private static let filterContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private static func filtered(_ image: CGImage, style: AnnotationStyle) -> CGImage? {
        let input = CIImage(cgImage: image)
        let name = style.maskEffect == .pixelate ? "CIPixellate" : "CIGaussianBlur"
        let parameter = style.maskEffect == .pixelate ? kCIInputScaleKey : kCIInputRadiusKey
        let strength = style.maskEffect == .pixelate ? style.maskStrength : style.maskStrength / 2
        guard let output = CIFilter(name: name, parameters: [kCIInputImageKey: input.clampedToExtent(), parameter: strength])?.outputImage?.cropped(to: input.extent) else { return nil }
        return filterContext.createCGImage(output, from: input.extent)
    }
    private static func drawArrow(_ object: AnnotationObject, in context: CGContext) {
        let headLength = object.arrowHeadLength
        guard headLength > 0 else { return }
        let head = object.style.arrowHead
        let width = min(object.style.width, headLength * 0.55)
        let start = object.start, end = object.end, control = object.curveControl
        let chord = hypot(end.x - start.x, end.y - start.y)
        let inset = width * 0.7
        // 收短箭杆再画两翼，使圆端藏在箭尖内。弧线按原贝塞尔曲线截取。
        func trim(at endpoint: CGPoint) -> CGFloat {
            guard let control else { return min(0.45, inset / chord) }
            let tangent = hypot(control.x - endpoint.x, control.y - endpoint.y)
            return min(0.45, tangent > 0 ? inset / (2 * tangent) : sqrt(inset / chord))
        }
        let t0 = head == .double ? trim(at: start) : 0
        let t1 = 1 - trim(at: end)
        let shaftStart = object.arrowPoint(at: t0)
        let shaftEnd = object.arrowPoint(at: t1)
        context.setLineWidth(width)
        context.move(to: shaftStart)
        if let control {
            let dx = (1 - t0) * (control.x - start.x) + t0 * (end.x - control.x)
            let dy = (1 - t0) * (control.y - start.y) + t0 * (end.y - control.y)
            context.addQuadCurve(to: shaftEnd, control: CGPoint(x: shaftStart.x + dx * (t1 - t0), y: shaftStart.y + dy * (t1 - t0)))
        } else {
            context.addLine(to: shaftEnd)
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        arrowHead(at: end, from: control == end ? start : (control ?? start), length: headLength, open: head == .open, context: context)
        if head == .double {
            arrowHead(at: start, from: control == start ? end : (control ?? end), length: headLength, open: false, context: context)
        }
    }
    private static func arrowHead(at tip: CGPoint, from start: CGPoint, length: CGFloat, open: Bool, context: CGContext) {
        guard hypot(tip.x-start.x, tip.y-start.y) > 0 else { return }
        let angle = atan2(tip.y-start.y, tip.x-start.x)
        let spread: CGFloat = open ? 0.58 : 0.45
        let left = CGPoint(x: tip.x - length * cos(angle-spread), y: tip.y - length * sin(angle-spread))
        let right = CGPoint(x: tip.x - length * cos(angle+spread), y: tip.y - length * sin(angle+spread))
        context.move(to: left); context.addLine(to: tip); context.addLine(to: right)
        if open { context.strokePath() }
        else { context.closePath(); context.fillPath() }
    }
}
