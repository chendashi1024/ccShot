import AppKit

enum AnnotationTool: String, Codable, CaseIterable {
    case select, rectangle, ellipse, arrow, line, pen, text, mask, highlight, number
    var title: String {
        switch self {
        case .select: return "选择"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .text: return "文字"
        case .mask: return "遮挡"
        case .highlight: return "高亮"
        case .number: return "序号"
        }
    }
    var key: String { [.select: "v", .rectangle: "r", .ellipse: "o", .arrow: "a", .line: "l", .pen: "p", .text: "t", .mask: "m", .highlight: "h", .number: "n"][self]! }
}

struct AnnotationColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1
    static let palette = [AnnotationColor(red: 0.95, green: 0.25, blue: 0.25), AnnotationColor(red: 1, green: 0.55, blue: 0.1), AnnotationColor(red: 1, green: 0.84, blue: 0.1), AnnotationColor(red: 0.2, green: 0.75, blue: 0.4), AnnotationColor(red: 0.1, green: 0.5, blue: 1), AnnotationColor(red: 0.6, green: 0.35, blue: 0.95), AnnotationColor(red: 0.15, green: 0.15, blue: 0.17), AnnotationColor(red: 1, green: 1, blue: 1)]
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var valid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .systemRed
        red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent; alpha = rgb.alphaComponent
    }
}

enum MaskEffect: String, Codable, CaseIterable { case solid, pixelate, blur }
enum ArrowHead: String, Codable, CaseIterable { case filled, open, double }
struct AnnotationStyle: Codable, Equatable {
    var color = AnnotationColor.palette[0]
    var width: CGFloat = 4
    var filled = false
    var fillOpacity: CGFloat = 1
    var cornerRadius: CGFloat = 0
    var dashed = false
    var arrowHead = ArrowHead.filled
    var maskEffect = MaskEffect.solid
    var maskBrush = false
    var maskStrength: CGFloat = 16
    var fontSize: CGFloat = 24
    var bold = false
    var textBackground = false
    var backgroundColor = AnnotationColor(red:1,green:0.96,blue:0.72)
    var valid: Bool { fontSize.isFinite && (8...200).contains(fontSize) && backgroundColor.valid && fillOpacity.isFinite && (0...1).contains(fillOpacity) && color.valid && width.isFinite && (1...80).contains(width) && maskStrength.isFinite && (4...80).contains(maskStrength) && cornerRadius.isFinite && (0...80).contains(cornerRadius) }
    static func defaultScale(imageSize: CGSize, displayedWidth: CGFloat) -> CGFloat {
        guard displayedWidth > 0 else { return 1 }
        // 从画面上的点数换算成导出像素，小选区限制放大幅度。
        return max(0.65, min(4, imageSize.width / displayedWidth, min(imageSize.width, imageSize.height) / 128))
    }
    static func initial(_ tool: AnnotationTool, scale: CGFloat = 1) -> Self {
        func pixels(_ points: CGFloat, lower: CGFloat = 1, upper: CGFloat = 80) -> CGFloat {
            min(upper, max(lower, (points * scale).rounded()))
        }
        var style = Self()
        style.width = pixels(4)
        switch tool {
        case .arrow: style.width = pixels(6)
        case .rectangle: style.cornerRadius = pixels(3)
        case .text: style.fontSize = pixels(20, lower: 8, upper: 200)
        case .mask:
            style.width = pixels(24)
            style.maskStrength = pixels(16, lower: 4)
            style.color = .palette[6]
        case .highlight:
            style.width = pixels(20)
            style.color = .palette[2]
        default: break
        }
        return style
    }
}

struct AnnotationObject: Equatable {
    let id: UUID
    let tool: AnnotationTool
    var style: AnnotationStyle
    var start: CGPoint
    var end: CGPoint
    var curveControl: CGPoint?
    var points: [CGPoint] = []
    var number: Int = 1
    var text = ""
    var textLayoutWidth: CGFloat = 360
    init(id: UUID = UUID(), tool: AnnotationTool, style: AnnotationStyle, start: CGPoint, end: CGPoint, points: [CGPoint] = [], number: Int = 1, text: String = "", textLayoutWidth: CGFloat = 360) {
        self.id = id; self.tool = tool; self.style = style; self.start = start; self.end = end; self.points = points; self.number = number; self.text = text; self.textLayoutWidth = textLayoutWidth
    }
    // 中间拖点始终落在曲线上；二次贝塞尔控制点由它反推。
    var arrowMidpoint: CGPoint { arrowPoint(at: 0.5) }
    var arrowHeadLength: CGFloat {
        let box = strokePath.boundingBoxOfPath
        let fraction = style.arrowHead == .double ? 0.45 : 0.7
        return min(max(12, style.width * 3), hypot(box.width, box.height) * fraction)
    }
    func arrowPoint(at t: CGFloat) -> CGPoint {
        let c = curveControl ?? CGPoint(x:(start.x+end.x)/2,y:(start.y+end.y)/2)
        let u = 1-t
        return CGPoint(x:u*u*start.x+2*u*t*c.x+t*t*end.x,y:u*u*start.y+2*u*t*c.y+t*t*end.y)
    }
    var strokePath: CGPath {
        let path = CGMutablePath(); path.move(to:start)
        if tool == .arrow, let curveControl { path.addQuadCurve(to:end,control:curveControl) }
        else { path.addLine(to:end) }
        return path
    }
    var bounds: CGRect {
        if tool == .arrow, curveControl != nil {
            let box = strokePath.boundingBoxOfPath
            return CGRect(x:box.minX,y:box.minY,width:max(1,box.width),height:max(1,box.height))
        }
        let values = points.isEmpty ? [start, end] : points
        let xs = values.map(\.x), ys = values.map(\.y)
        let minX = xs.min() ?? start.x, minY = ys.min() ?? start.y
        return CGRect(x: minX, y: minY, width: max(1, (xs.max() ?? end.x) - minX), height: max(1, (ys.max() ?? end.y) - minY))
    }
    var occlusion: CGRect? {
        if tool == .mask { return bounds.insetBy(dx:style.maskBrush ? -style.width/2 : -1,dy:style.maskBrush ? -style.width/2 : -1) }
        if [.rectangle,.ellipse].contains(tool) && style.filled && style.color.alpha > 0 && style.fillOpacity > 0 { return bounds }
        if tool == .number || tool == .text && style.textBackground && style.backgroundColor.alpha > 0 { return bounds }
        return nil
    }
    func moved(by delta: CGPoint) -> Self {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        copy.end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
        copy.curveControl = curveControl.map { CGPoint(x:$0.x+delta.x,y:$0.y+delta.y) }
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return copy
    }
    @MainActor func resized(to rect: CGRect) -> Self {
        let previous = bounds
        if tool == .text {
            var copy = self
            let factor = min(rect.width/previous.width,rect.height/previous.height)
            copy.style.fontSize = min(200,max(8,style.fontSize*factor))
            copy.textLayoutWidth = max(2*AnnotationTextLayout.inset+1,textLayoutWidth*copy.style.fontSize/style.fontSize)
            let size = AnnotationTextLayout.size(text,style:copy.style,maxWidth:copy.textLayoutWidth)
            copy.start = rect.origin; copy.end = CGPoint(x:rect.minX+size.width,y:rect.minY+size.height)
            return copy
        }
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + (p.x - previous.minX) / previous.width * rect.width, y: rect.minY + (p.y - previous.minY) / previous.height * rect.height) }
        var copy = self; copy.start = map(start); copy.end = map(end); copy.points = points.map(map); copy.curveControl = curveControl.map(map); return copy
    }
    func hit(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((p.x-a.x)*dx + (p.y-a.y)*dy) / length))
            return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
        }
        let padding = tolerance + style.width / 2
        switch tool {
        case .arrow:
            let c = curveControl ?? start
            let length = hypot(c.x-start.x,c.y-start.y)+hypot(end.x-c.x,end.y-c.y)
            let steps = max(1,min(4096,Int(ceil(length/4))))
            var previous = start
            for index in 1...steps {
                let next = arrowPoint(at:CGFloat(index)/CGFloat(steps))
                if distance(point,previous,next) <= padding { return true }
                previous = next
            }
            let headRadius = max(padding, arrowHeadLength)
            return hypot(point.x-end.x,point.y-end.y) <= headRadius || style.arrowHead == .double && hypot(point.x-start.x,point.y-start.y) <= headRadius
        case .line: return distance(point,start,end) <= padding
        case .text: return bounds.insetBy(dx:-tolerance,dy:-tolerance).contains(point)
        case .mask where !style.maskBrush: return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .pen, .highlight, .mask:
            if points.count == 1 { return distance(point, points[0], points[0]) <= padding }
            return zip(points, points.dropFirst()).contains { distance(point, $0.0, $0.1) <= padding }
        case .ellipse, .number:
            let b = bounds, x = (point.x - b.midX) / max(1, b.width / 2), y = (point.y - b.midY) / max(1, b.height / 2)
            let radius = sqrt(x*x+y*y)
            return style.filled || tool == .number ? radius <= 1 + padding / max(1, min(b.width,b.height)/2) : abs(radius - 1) <= padding / max(1,min(b.width,b.height)/2)
        case .rectangle:
            if style.filled { return bounds.insetBy(dx: -padding, dy: -padding).contains(point) }
            return bounds.insetBy(dx: -padding, dy: -padding).contains(point) && !bounds.insetBy(dx: padding, dy: padding).contains(point)
        case .select: return false
        }
    }
}

struct AnnotationState: Equatable {
    var objects: [AnnotationObject] = []
    var nextNumber = 1
    var occlusions: [CGRect] { objects.compactMap(\.occlusion) }
    var safeTextOverlays: [AnnotationObject] {
        objects.indices.compactMap { index in
            let object = objects[index]
            guard object.tool == .text else { return nil }
            let laterOcclusions = objects.dropFirst(index+1).compactMap(\.occlusion)
            return laterOcclusions.contains(where:{$0.intersects(object.bounds)}) ? nil : object
        }
    }
}

@MainActor final class AnnotationDocument {
    let baseImage: CGImage
    private(set) var state = AnnotationState()
    private var undoStates: [AnnotationState] = []
    private var redoStates: [AnnotationState] = []
    private var transaction: AnnotationState?
    private(set) var revision = 0
    var onChange: (() -> Void)?
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    var inTransaction: Bool { transaction != nil }
    init(image: CGImage) { baseImage = image }
    @discardableResult func commit(_ value: AnnotationState) -> Bool {
        guard state != value else { return false }
        if transaction == nil { undoStates.append(state); redoStates.removeAll() }
        state = value; revision += 1; onChange?(); return true
    }
    func beginTransaction() { if transaction == nil { transaction = state } }
    func endTransaction() {
        guard let previous = transaction else { return }
        transaction = nil
        if state != previous { undoStates.append(previous); redoStates.removeAll() }
        revision += 1; onChange?()
    }
    func undo() {
        guard !inTransaction, let value = undoStates.popLast() else { return }
        redoStates.append(state); state = value; revision += 1; onChange?()
    }
    func redo() {
        guard !inTransaction, let value = redoStates.popLast() else { return }
        undoStates.append(state); state = value; revision += 1; onChange?()
    }
    func copied() -> AnnotationDocument {
        let copy = AnnotationDocument(image: baseImage)
        copy.state = state; copy.undoStates = undoStates; copy.redoStates = redoStates; copy.revision = revision
        return copy
    }
}
