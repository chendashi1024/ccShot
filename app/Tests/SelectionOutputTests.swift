import AppKit

@main struct SelectionOutputTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let context = CGContext(data:nil,width:400,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<240 {
            for x in 0..<400 {
                context.setFillColor(NSColor(calibratedRed:CGFloat(x)/400,green:CGFloat(y)/240,blue:0.7,alpha:1).cgColor)
                context.fill(CGRect(x:x,y:y,width:1,height:1))
            }
        }
        let source = context.makeImage()!
        let view = SelectionView(image:source,frame:CGRect(x:0,y:0,width:1000,height:600))
        func buttons(_ root: NSView) -> [NSButton] {
            root.subviews.flatMap { child in (child as? NSButton).map { [$0] } ?? buttons(child) }
        }
        let actions = buttons(view)
        let expected = [("复制",SelectionAction.copy),("保存",.save),("钉住",.pin)]
        for (title,action) in expected {
            guard let button=actions.first(where:{$0.title==title}) else {
                print("失败：框选后缺少可见的\(title)按钮");exit(1)
            }
            var results:[(CGImage,NSRect,SelectionAction)] = []
            view.onConfirm = {results.append(($0,$1,$2))}
            view.selectRegion(CGRect(x:100,y:120,width:300,height:240))
            precondition(!button.isHiddenOrHasHiddenAncestor,"有效选区必须显示输出入口")
            button.performClick(nil)
            precondition(results.count==1 && results[0].2==action,"输出按钮必须调用对应动作一次")
            let image=results[0].0
            precondition(image.width==120 && image.height==96,"输出必须裁自当前源像素选区")
            for point in [(0,0),(67,36),(119,95)] {
                precondition(PixelSampler.color(in:image,x:point.0,y:point.1)?.hex == PixelSampler.color(in:source,x:40+point.0,y:96+point.1)?.hex,"不能返回旧图或选区外像素")
            }
            view.selectRegion(.zero)
            button.performClick(nil)
            precondition(results.count==1,"选区清空后不能输出旧缓存")
        }
        view.selectRegion(CGRect(x:900,y:550,width:100,height:50))
        let row=actions[0].superview!
        precondition(view.bounds.insetBy(dx:7,dy:7).contains(row.frame),"屏边选区不能把输出按钮推到屏幕外")
        print("通过：框选后的复制/保存/钉住按钮、当前裁剪像素、空选区拒绝与屏边布局")
    }
}
