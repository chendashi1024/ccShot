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
        let tools:[(String,AnnotationTool)] = [("选择",.select),("箭头",.arrow),("画框",.rectangle),("文字",.text),("画笔",.pen),("遮挡",.mask),("高亮",.highlight),("序号",.number)]
        for (title,tool) in tools {
            guard let button=actions.first(where:{$0.title==title}) else {
                print("失败：框选后无法直接点选\(title)，仍须先点完成");exit(1)
            }
            var delivered:SelectionAction?;var size:CGSize?
            view.onConfirm = {image,_,action in delivered=action;size=CGSize(width:image.width,height:image.height)}
            view.selectRegion(CGRect(x:100,y:120,width:300,height:240))
            precondition(!button.isHiddenOrHasHiddenAncestor)
            button.performClick(nil)
            precondition(delivered == .annotate(tool) && size == CGSize(width:120,height:96),"必须把当前选区和选中的工具交给编辑器")
            delivered=nil;view.selectRegion(.zero);button.performClick(nil)
            precondition(delivered==nil,"清空选区后不能用上一次工具操作旧图")
        }
        view.selectRegion(CGRect(x:900,y:550,width:100,height:50))
        let row=actions[0].superview!
        precondition(view.bounds.insetBy(dx:7,dy:7).contains(view.convert(row.bounds, from: row)),"屏边选区不能把输出按钮推到屏幕外")
        let narrow = SelectionView(image: source, frame: CGRect(x: 0, y: 0, width: 360, height: 300))
        narrow.selectRegion(CGRect(x: 210, y: 140, width: 140, height: 90))
        let panel = narrow.subviews.compactMap { $0 as? FloatingControls }.first!
        let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
        let last = buttons(panel).last!
        precondition(narrow.bounds.insetBy(dx: 12, dy: 0).contains(panel.frame))
        precondition(scroll.hasHorizontalScroller && scroll.frame.minX == 16 && panel.bounds.maxX - scroll.frame.maxX == 16)
        precondition(last.frame.width >= last.intrinsicContentSize.width, "窄屏不能压缩或截断边缘按钮")
        last.scrollToVisible(last.bounds)
        precondition(scroll.documentVisibleRect.contains(panel.stack.convert(last.bounds, from: last)), "最后一个按钮可完整滚动到可见范围")
        let direct=SelectionView(image:source,frame:CGRect(x:0,y:0,width:1000,height:600))
        direct.automaticallyEdit=true
        var automatic:[(CGImage,SelectionAction)]=[]
        direct.onConfirm={image,_,action in automatic.append((image,action))}
        direct.selectAll(nil)
        precondition(automatic.count==1 && automatic[0].0.width==400 && automatic[0].0.height==240 && automatic[0].1 == .edit,"全屏选区应直接进入可选字编辑，不必再点完成")
        direct.selectRegion(CGRect(x:100,y:120,width:300,height:240))
        let release=NSEvent.mouseEvent(with:.leftMouseUp,location:CGPoint(x:400,y:360),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0)!
        direct.mouseUp(with:release)
        precondition(automatic.count==2 && automatic[1].0.width==120 && automatic[1].0.height==96 && automatic[1].1 == .edit,"框选松手直接交付当前裁剪")
        direct.selectRegion(.zero);direct.mouseUp(with:release)
        precondition(automatic.count==2,"空选区松手不能交付旧图")
        print("通过：框选直接选择八个常用工具、复制/保存/钉住、当前裁剪像素与空选区拒绝")
    }
}
