import AppKit

struct WindowTarget: Equatable {
    let id: UInt32
    let ownerPID: Int32
    let rect: CGRect

    static func localRect(quartzFrame: CGRect, screenFrame: CGRect, primaryTop: CGFloat) -> CGRect? {
        guard let converted=editorRect(quartzFrame:quartzFrame,screenFrame:screenFrame,primaryTop:primaryTop) else {return nil}
        return converted.intersection(CGRect(origin:.zero,size:screenFrame.size))
    }
    static func editorRect(quartzFrame:CGRect,screenFrame:CGRect,primaryTop:CGFloat)->CGRect? {
        let values=[quartzFrame.minX,quartzFrame.minY,quartzFrame.width,quartzFrame.height,screenFrame.minX,screenFrame.minY,screenFrame.width,screenFrame.height,primaryTop]
        guard values.allSatisfy({$0.isFinite}),quartzFrame.width>0,quartzFrame.height>0,screenFrame.width>0,screenFrame.height>0 else {return nil}
        let rect=CGRect(x:quartzFrame.minX-screenFrame.minX,y:primaryTop-quartzFrame.maxY-screenFrame.minY,width:quartzFrame.width,height:quartzFrame.height)
        let visible=rect.intersection(CGRect(origin:.zero,size:screenFrame.size))
        return visible.isNull || visible.isEmpty ? nil : rect
    }
    // 输入按系统前后顺序排列，重叠处只命中最前面的可捕获窗口。
    static func hit(_ point: CGPoint, in ordered: [WindowTarget]) -> WindowTarget? {
        ordered.first { !$0.rect.isEmpty && $0.rect.contains(point) }
    }
}
