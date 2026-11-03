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
        case .line, .arrow:
            context.move(to: object.start); context.addLine(to: object.end); context.strokePath()
            if object.tool == .arrow {
                context.setLineDash(phase: 0, lengths: [])
                arrow(at: object.end, from: object.start, style: style, context: context)
                if style.arrowHead == .double { arrow(at: object.start, from: object.end, style: style, context: context) }
            }
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
            guard let source = context.makeImage(), let filtered = filtered(source, style: style) else { return false }
            context.setLineDash(phase: 0, lengths: [])
            if style.maskBrush {
                guard let first = object.points.first else { return true }
                context.move(to: first)
                if object.points.count == 1 { context.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
                else { for point in object.points.dropFirst() { context.addLine(to: point) } }
                context.replacePathWithStrokedPath(); context.clip()
            } else { context.clip(to: object.bounds) }
            context.draw(filtered, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
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
    private static func arrow(at tip: CGPoint, from start: CGPoint, style: AnnotationStyle, context: CGContext) {
        guard hypot(tip.x-start.x, tip.y-start.y) > 0 else { return }
        let angle = atan2(tip.y-start.y, tip.x-start.x)
        let size = max(12, style.width * 3)
        let left = CGPoint(x: tip.x - size*cos(angle-0.45), y: tip.y - size*sin(angle-0.45))
        let right = CGPoint(x: tip.x - size*cos(angle+0.45), y: tip.y - size*sin(angle+0.45))
        context.move(to: left); context.addLine(to: tip); context.addLine(to: right)
        if style.arrowHead == .open { context.strokePath() }
        else { context.closePath(); context.fillPath() }
    }
}
