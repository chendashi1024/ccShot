import AppKit

@main struct ScreenshotLayoutTests {
    static func main() {
        let source=CGSize(width:1440,height:900),region=CGRect(x:362,y:280,width:716,height:450)
        guard let value=ScreenshotLayout.make(capture:source,region:region,viewport:source,toolbar:CGSize(width:956,height:56),parameters:CGSize(width:512,height:116)) else {
            print("失败：尚无保持选区原位的浮动布局");exit(1)
        }
        precondition(value.background==CGRect(origin:.zero,size:source))
        precondition(value.image==region,"参数面板不能挤动或重排截图")
        precondition(value.toolbar==CGRect(x:242,y:196,width:956,height:56),"工具条应在原选区下方居中")
        precondition(value.parameters==CGRect(x:250,y:68,width:512,height:116),"参数紧靠工具条下方且按内容定宽")
        let select=ScreenshotLayout.make(capture:source,region:region,viewport:source,toolbar:CGSize(width:956,height:56),parameters:.zero)!
        precondition(select.image==region && select.toolbar==value.toolbar && select.parameters==nil,"切换工具不能让截图或首排跳动")
        for box in [CGRect(x:0,y:0,width:100,height:100),CGRect(x:1300,y:790,width:140,height:110),CGRect(origin:.zero,size:source)] {
            let layout=ScreenshotLayout.make(capture:source,region:box,viewport:source,toolbar:CGSize(width:956,height:56),parameters:CGSize(width:512,height:116))!
            let safe=CGRect(x:12,y:12,width:1416,height:876)
            precondition(layout.image==box && safe.contains(layout.toolbar) && safe.contains(layout.parameters!),"四角与整屏不能把操作推出屏幕或缩小截图")
            if box.height==100 {precondition(layout.parameters!.minY>=box.maxY,"下边缘选区时整组参数应避让到上方")}
        }
        let scaled=ScreenshotLayout.make(capture:source,region:region,viewport:CGSize(width:720,height:500),toolbar:CGSize(width:956,height:56),parameters:CGSize(width:512,height:116))!
        precondition(scaled.background==CGRect(x:0,y:25,width:720,height:450))
        precondition(scaled.image==CGRect(x:181,y:165,width:358,height:225),"屏幕改变后按同一比例映射，不拉伸图片")
        precondition(ScreenshotLayout.make(capture:.zero,region:region,viewport:source,toolbar:CGSize(width:956,height:56),parameters:.zero)==nil)
        precondition(ScreenshotLayout.make(capture:source,region:CGRect(x:-1,y:0,width:10,height:10),viewport:source,toolbar:CGSize(width:956,height:56),parameters:.zero)==nil)
        let windowRegion=CGRect(x:-120,y:300,width:800,height:500)
        let windowLayout=ScreenshotLayout.make(capture:source,region:windowRegion,viewport:source,toolbar:CGSize(width:956,height:56),parameters:CGSize(width:512,height:116),allowsOutsideRegion:true)!
        precondition(windowLayout.image==windowRegion,"完整窗口不能被裁掉或挤压到可见高亮框")
        precondition(CGRect(x:12,y:12,width:1416,height:876).contains(windowLayout.toolbar))
        precondition(ScreenshotLayout.make(capture:source,region:CGRect(x:1500,y:0,width:100,height:100),viewport:source,toolbar:CGSize(width:956,height:56),parameters:.zero,allowsOutsideRegion:true)==nil,"窗口完全离开当前屏幕时拒绝原位交接")
        print("通过：原位图像、就近浮动、紧凑参数、屏边避让与等比视口映射")
    }
}
