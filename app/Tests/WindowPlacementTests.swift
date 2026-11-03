import AppKit

@main struct WindowPlacementTests {
    static func main() {
        let screen=CGRect(x:0,y:0,width:1440,height:900)
        let partiallyOutside=CGRect(x:-120,y:100,width:800,height:500)
        guard WindowTarget.editorRect(quartzFrame:partiallyOutside,screenFrame:screen,primaryTop:900) == CGRect(x:-120,y:300,width:800,height:500) else {
            print("失败：窗口原位编辑必须保留完整图像位置，不能把屏边高亮框当成完整窗口");exit(1)
        }
        precondition(WindowTarget.localRect(quartzFrame:partiallyOutside,screenFrame:screen,primaryTop:900)==CGRect(x:0,y:300,width:680,height:500),"高亮仍只能显示当前屏内部分")
        precondition(WindowTarget.editorRect(quartzFrame:CGRect(x:-1400,y:200,width:400,height:300),screenFrame:CGRect(x:-1280,y:0,width:1280,height:720),primaryTop:900)==CGRect(x:-120,y:400,width:400,height:300),"负坐标副屏保留窗口完整位置")
        precondition(WindowTarget.editorRect(quartzFrame:CGRect(x:300,y:-100,width:500,height:500),screenFrame:CGRect(x:0,y:900,width:1440,height:900),primaryTop:900)==CGRect(x:300,y:-400,width:500,height:500),"上方副屏使用主屏坐标原点翻转")
        precondition(WindowTarget.editorRect(quartzFrame:CGRect(x:1600,y:100,width:100,height:100),screenFrame:screen,primaryTop:900)==nil,"捕获期间已移走的窗口不应强放到原屏")
        precondition(WindowTarget.editorRect(quartzFrame:CGRect(x:0,y:0,width:0,height:100),screenFrame:screen,primaryTop:900)==nil)
        print("通过：窗口原位、贴边完整尺寸、负坐标副屏、上方屏与移走拒绝")
    }
}
