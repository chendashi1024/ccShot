import AppKit

enum AnnotationTool: String, Codable, CaseIterable {
    case select, rectangle, ellipse, arrow, line, pen, highlight, number
    var title: String {
        switch self {
        case .select: return "选择"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .pen: return "画笔"
        case .highlight: return "高亮"
        case .number: return "序号"
        }
    }
    var key: String { [.select: "v", .rectangle: "r", .ellipse: "o", .arrow: "a", .line: "l", .pen: "p", .highlight: "h", .number: "n"][self]! }
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

enum ArrowHead: String, Codable, CaseIterable { case filled, open, double }
struct AnnotationStyle: Codable, Equatable {
    var color = AnnotationColor.palette[0]
    var width: CGFloat = 4
    var filled = false
    var cornerRadius: CGFloat = 0
    var dashed = false
    var arrowHead = ArrowHead.filled
    var valid: Bool { color.valid && width.isFinite && (1...80).contains(width) && cornerRadius.isFinite && (0...80).contains(cornerRadius) }
    static func initial(_ tool: AnnotationTool) -> Self {
        var style = Self()
        if tool == .highlight { style.width = 18; style.color = .palette[2] }
        if tool == .number { style.width = 6 }
        return style
    }
}

struct AnnotationObject: Equatable {
    let id: UUID
    let tool: AnnotationTool
    var style: AnnotationStyle
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var number: Int = 1
    init(id: UUID = UUID(), tool: AnnotationTool, style: AnnotationStyle, start: CGPoint, end: CGPoint, points: [CGPoint] = [], number: Int = 1) {
        self.id = id; self.tool = tool; self.style = style; self.start = start; self.end = end; self.points = points; self.number = number
    }
    var bounds: CGRect {
        let values = points.isEmpty ? [start, end] : points
        let xs = values.map(\.x), ys = values.map(\.y)
        let minX = xs.min() ?? start.x, minY = ys.min() ?? start.y
        return CGRect(x: minX, y: minY, width: max(1, (xs.max() ?? end.x) - minX), height: max(1, (ys.max() ?? end.y) - minY))
    }
    func moved(by delta: CGPoint) -> Self {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
        copy.end = CGPoint(x: end.x + delta.x, y: end.y + delta.y)
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return copy
    }
    func resized(to rect: CGRect) -> Self {
        let previous = bounds
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + (p.x - previous.minX) / previous.width * rect.width, y: rect.minY + (p.y - previous.minY) / previous.height * rect.height) }
        var copy = self; copy.start = map(start); copy.end = map(end); copy.points = points.map(map); return copy
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
        case .line, .arrow: return distance(point, start, end) <= padding || (tool == .arrow && hypot(point.x-end.x, point.y-end.y) <= max(12, style.width * 3))
        case .pen, .highlight:
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
