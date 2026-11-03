import AppKit

@main struct GeometryTests {
    static func main() {
        let canvas = CGSize(width: 1440, height: 900)
        let image = CGSize(width: 2880, height: 1800)
        precondition(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), canvas: canvas, image: image) == CGRect(x: 20, y: 1660, width: 200, height: 100), "Retina 的 Y 翻转与尺寸应精确")
        precondition(CaptureGeometry.pixelRect(CGRect(x: -5, y: -5, width: 15, height: 15), canvas: canvas, image: image) == CGRect(x: 0, y: 1780, width: 20, height: 20), "边缘必须裁入图像")
        precondition(CaptureGeometry.pixelRect(.zero, canvas: canvas, image: image) == nil, "零面积不能输出")
        precondition(CaptureGeometry.pixelRect(CGRect(x: 2000, y: 0, width: 10, height: 10), canvas: canvas, image: image) == nil, "屏幕外不能输出旧图")
        precondition(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), canvas: CGSize(width: 1280, height: 720), image: CGSize(width: 1280, height: 720)) == CGRect(x: 10, y: 650, width: 100, height: 50), "1x 显示器不能套用主屏比例")
        let scaledCanvas = CGSize(width: 1512, height: 982)
        let scaledImage = CGSize(width: 2560, height: 1664)
        for pixels in [CGRect(x: 17, y: 35, width: 501, height: 333), CGRect(x: 0, y: 0, width: 2560, height: 1664)] {
            let visible = CaptureGeometry.viewRect(pixels, canvas: scaledCanvas, image: scaledImage)
            precondition(CaptureGeometry.pixelRect(visible, canvas: scaledCanvas, image: scaledImage) == pixels, "可见框与裁剪像素必须往返一致")
        }
        print("通过：Retina、1x、Y 翻转、边缘裁剪、无效选区")
    }
}
