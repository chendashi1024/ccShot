import AppKit

enum SelectionHandle: CaseIterable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

    var axes: (CGFloat, CGFloat) {
        switch self {
        case .bottomLeft: return (0, 0)
        case .bottom: return (0.5, 0)
        case .bottomRight: return (1, 0)
        case .right: return (1, 0.5)
        case .topRight: return (1, 1)
        case .top: return (0.5, 1)
        case .topLeft: return (0, 1)
        case .left: return (0, 0.5)
        }
    }
    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + axes.0 * rect.width, y: rect.minY + axes.1 * rect.height)
    }
    func resize(_ rect: CGRect, toward point: CGPoint, canvas: CGSize, minimum: CGSize) -> CGRect {
        func limits(_ lower: CGFloat, _ upper: CGFloat, _ pointer: CGFloat, _ axis: CGFloat, _ extent: CGFloat, _ minSize: CGFloat) -> (CGFloat, CGFloat) {
            guard axis != 0.5 else { return (lower, upper) }
            let fixed = axis == 0 ? upper : lower
            var moving = min(max(0, pointer), extent)
            let size = min(extent, minSize)
            if abs(moving - fixed) < size {
                moving = moving <= fixed && fixed >= size ? fixed - size : min(extent, fixed + size)
                if abs(moving - fixed) < size { moving = max(0, fixed - size) }
            }
            return (min(moving, fixed), max(moving, fixed))
        }
        let (x0, x1) = limits(rect.minX, rect.maxX, point.x, axes.0, canvas.width, minimum.width)
        let (y0, y1) = limits(rect.minY, rect.maxY, point.y, axes.1, canvas.height, minimum.height)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
