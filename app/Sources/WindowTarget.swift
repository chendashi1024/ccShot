import AppKit

struct WindowTarget: Equatable {
    let id: UInt32
    let ownerPID: Int32
    let rect: CGRect

    static func localRect(quartzFrame: CGRect, screenFrame: CGRect, primaryTop: CGFloat) -> CGRect? {
        guard [quartzFrame.minX, quartzFrame.minY, quartzFrame.width, quartzFrame.height, primaryTop].allSatisfy({ $0.isFinite }) else { return nil }
        let converted = CGRect(x: quartzFrame.minX - screenFrame.minX,
                               y: primaryTop - quartzFrame.maxY - screenFrame.minY,
                               width: quartzFrame.width, height: quartzFrame.height)
        let clipped = converted.intersection(CGRect(origin: .zero, size: screenFrame.size))
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }
    // 输入按系统前后顺序排列，重叠处只命中最前面的可捕获窗口。
    static func hit(_ point: CGPoint, in ordered: [WindowTarget]) -> WindowTarget? {
        ordered.first { !$0.rect.isEmpty && $0.rect.contains(point) }
    }
}
