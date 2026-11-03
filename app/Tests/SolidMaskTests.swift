import AppKit

@main struct SolidMaskTests {
    @MainActor static func main() {
        let initial=AnnotationStyle.initial(.mask)
        guard initial.maskEffect.rawValue=="solid" else {print("失败：核心遮挡默认仍不是实心");exit(1)}
        let context=CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:200,height:100))
        let base=context.makeImage()!
        for brush in [false,true] {
            var style=initial;style.maskBrush=brush;style.width=24;style.color=AnnotationColor(red:0,green:0,blue:0,alpha:0.1)
            let object=AnnotationObject(tool:.mask,style:style,start:CGPoint(x:40,y:20),end:CGPoint(x:120,y:80),points:brush ? [CGPoint(x:60,y:25),CGPoint(x:60,y:75)] : [])
            let image=AnnotationRenderer.render(base:base,objects:[object])!
            precondition(PixelSampler.color(in:image,x:60,y:49)!.hex=="#000000","实心遮挡必须完全不透明，不继承颜色Alpha")
            precondition(PixelSampler.color(in:image,x:160,y:49)!.hex=="#FFFFFF","遮挡外不能变化")
            let doc=AnnotationDocument(image:base);var state=doc.state;state.objects=[object];doc.commit(state)
            doc.undo();precondition(doc.state.objects.isEmpty);doc.redo();precondition(doc.state.objects==[object])
            precondition(doc.copied().state==doc.state,"钉图必须保留实心对象")
        }
        for effect in [MaskEffect.pixelate,.blur] {
            var oldStyle=initial;oldStyle.maskEffect=effect;oldStyle.color = .palette[0]
            let encoded=try! JSONEncoder().encode(oldStyle)
            precondition(try! JSONDecoder().decode(AnnotationStyle.self,from:encoded)==oldStyle,"已有马赛克/模糊样式不能被新默认覆盖")
        }
        var fractional=initial;fractional.color=AnnotationColor(red:0,green:0,blue:0)
        let object=AnnotationObject(tool:.mask,style:fractional,start:CGPoint(x:40.9,y:20.9),end:CGPoint(x:120.1,y:80.1))
        let aligned=AnnotationRenderer.render(base:base,objects:[object])!
        precondition(PixelSampler.color(in:aligned,x:40,y:79)!.hex=="#000000","实心框按完整源像素覆盖边缘")
        precondition(PixelSampler.color(in:aligned,x:39,y:79)!.hex=="#FFFFFF")
        print("通过：实心默认、框选/涂抹不透明、区域外不变、撤销重做与独立副本")
    }
}
