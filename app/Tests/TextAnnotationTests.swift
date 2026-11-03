import AppKit

@main struct TextAnnotationTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var style = AnnotationStyle.initial(.text)
        let text = "中文 V B C 123\n第二行 😀"
        let size = AnnotationTextLayout.size(text, style:style, maxWidth:300)
        precondition(size.width <= 300 && size.height > style.fontSize * 2, "中文、换行和emoji须有完整布局")
        style.bold = true; style.fontSize = 32
        let larger = AnnotationTextLayout.size(text,style:style,maxWidth:300)
        precondition(larger.height > size.height)
        let object = AnnotationObject(tool:.text,style:style,start:CGPoint(x:20,y:20),end:CGPoint(x:20+larger.width,y:20+larger.height),text:text,textLayoutWidth:300)
        let moved = object.moved(by:CGPoint(x:15,y:7))
        precondition(moved.text == text && moved.bounds.origin == CGPoint(x:35,y:27))
        let scaled = object.resized(to:CGRect(x:10,y:10,width:object.bounds.width*1.5,height:object.bounds.height*1.5))
        precondition(scaled.style.fontSize > object.style.fontSize && scaled.text == text)
        print("通过：中文换行、字号、加粗、移动与文字缩放")
    }
}
