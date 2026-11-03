import AppKit

@main struct SafeTextGeometryTests {
    static func main() {
        let line = CGRect(x: 20,y:100,width:300,height:30)
        let safe = CGRect(x:20,y:30,width:250,height:30)
        let partialMask = CGRect(x:140,y:110,width:10,height:10)
        let blocked = SafeTextImage.regionsToSuppress(textRegions: [line,safe], occlusions:[partialMask], size:CGSize(width:400,height:200))
        precondition(blocked.count == 1 && blocked[0].contains(line), "部分遮挡必须屏蔽整个相交识别单元")
        precondition(SafeTextImage.regionsToSuppress(textRegions:[line],occlusions:[],size:CGSize(width:400,height:200)).isEmpty)
        let border = SafeTextImage.regionsToSuppress(textRegions:[CGRect(x:0,y:0,width:30,height:20)],occlusions:[CGRect(x:0,y:0,width:1,height:1)],size:CGSize(width:400,height:200))
        precondition(border[0].minX == 0 && border[0].minY == 0, "安全扩边不得越出图片")
        print("通过：部分遮挡整单元屏蔽、无相交保留与图片边界")
    }
}
