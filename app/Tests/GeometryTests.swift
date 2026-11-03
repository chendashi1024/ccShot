import AppKit

@main struct GeometryTests {
    static func main() {
        let canvas = CGSize(width: 1440, height: 900)
        let image = CGSize(width: 2880, height: 1800)
        precondition(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), canvas: canvas, image: image) == CGRect(x: 20, y: 1660, width: 200, height: 100), "Retina 的 Y 翻转与尺寸应精确")
        precondition(CaptureGeometry.pixelRect(CGRect(x: -5, y: -5, width: 15, height: 15), canvas: canvas, image: image) == CGRect(x: 0, y: 1780, width: 20, height: 20), "边缘必须裁入图像")
        precondition(CaptureGeometry.pixelRect(.zero, canvas: canvas, image: image) == nil, "零面积不能输出")
        precondition(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 100.00000000000001, height: 50), canvas: canvas, image: image) == CGRect(x: 20, y: 1660, width: 200, height: 100), "整像素边界的机器精度误差不应向外扩一像素")
        precondition(CaptureGeometry.pixelRect(CGRect(x: 2000, y: 0, width: 10, height: 10), canvas: canvas, image: image) == nil, "屏幕外不能输出旧图")
        precondition(CaptureGeometry.pixelRect(CGRect(x: 10, y: 20, width: 100, height: 50), canvas: CGSize(width: 1280, height: 720), image: CGSize(width: 1280, height: 720)) == CGRect(x: 10, y: 650, width: 100, height: 50), "1x 显示器不能套用主屏比例")
        let scaledCanvas = CGSize(width: 1512, height: 982)
        let scaledImage = CGSize(width: 2560, height: 1664)
        for pixels in [CGRect(x: 17, y: 35, width: 501, height: 333), CGRect(x: 0, y: 0, width: 2560, height: 1664)] {
            let visible = CaptureGeometry.viewRect(pixels, canvas: scaledCanvas, image: scaledImage)
            precondition(CaptureGeometry.pixelRect(visible, canvas: scaledCanvas, image: scaledImage) == pixels, "可见框与裁剪像素必须往返一致")
        }
        let demoCanvas = CGSize(width: 1728, height: 1117)
        let demoRegion = CGRect(x: demoCanvas.width * 0.2, y: demoCanvas.height * 0.25, width: demoCanvas.width * 0.6, height: demoCanvas.height * 0.5)
        precondition(CaptureGeometry.pixelRect(demoRegion, canvas: demoCanvas, image: CGSize(width: 1920, height: 460)) == CGRect(x: 384, y: 115, width: 1152, height: 230), "浮点误差不得使整像素边界多输出一列或一行")
        for canvas in [CGSize(width: 1440, height: 900), CGSize(width: 1728, height: 1117), CGSize(width: 1512, height: 982), CGSize(width: 1920, height: 1080)] {
            let pixels = CGRect(x: 384, y: 115, width: 1152, height: 230)
            let source = CGSize(width: 1920, height: 460)
            let visible = CaptureGeometry.viewRect(pixels, canvas: canvas, image: source)
            precondition(CaptureGeometry.pixelRect(visible, canvas: canvas, image: source) == pixels, "界面显示后再次裁剪不能扩大像素范围")
        }
        let initial = CGRect(x: 100, y: 100, width: 200, height: 100)
        precondition(SelectionHandle.topRight.resize(initial, toward: CGPoint(x: 350, y: 250), canvas: canvas, minimum: CGSize(width: 1, height: 1)) == CGRect(x: 100, y: 100, width: 250, height: 150), "右上控制点应保留对角")
        precondition(SelectionHandle.left.resize(initial, toward: CGPoint(x: 350, y: 999), canvas: canvas, minimum: CGSize(width: 1, height: 1)) == CGRect(x: 300, y: 100, width: 50, height: 100), "控制点跨越固定边仍应生成合法矩形")
        for handle in SelectionHandle.allCases {
            let resized = handle.resize(initial, toward: CGPoint(x: -100, y: 2000), canvas: canvas, minimum: CGSize(width: 1, height: 1))
            precondition(resized.width >= 1 && resized.height >= 1 && CGRect(origin: .zero, size: canvas).contains(resized), "所有控制点都应限制在屏内")
        }
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let colors = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        precondition(PixelSampler.color(in: colors, x: 0, y: 0)?.hex == "#FF0000", "取色应保留原图左上红色像素")
        precondition(PixelSampler.color(in: colors, x: 1, y: 0)?.rgb == "RGB(0, 255, 0)", "取色坐标应逐像素对应")
        precondition(PixelSampler.color(in: colors, x: 0, y: 1)?.hex == "#0000FF", "取色不能上下翻转")
        precondition(PixelSampler.color(in: colors, x: -1, y: 0) == nil && PixelSampler.color(in: colors, x: 2, y: 0) == nil, "越界不应返回旧色值")
        precondition(WindowTarget.localRect(quartzFrame: CGRect(x: 100, y: 100, width: 400, height: 300), screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), primaryTop: 900) == CGRect(x: 100, y: 500, width: 400, height: 300), "窗口高亮应翻转全局 Y 坐标")
        precondition(WindowTarget.localRect(quartzFrame: CGRect(x: -1200, y: 300, width: 300, height: 200), screenFrame: CGRect(x: -1280, y: 0, width: 1280, height: 720), primaryTop: 900) == CGRect(x: 80, y: 400, width: 300, height: 200), "左屏负坐标应映射到本屏")
        precondition(WindowTarget.localRect(quartzFrame: CGRect(x: 100, y: -800, width: 400, height: 300), screenFrame: CGRect(x: 0, y: 900, width: 1440, height: 900), primaryTop: 900) == CGRect(x: 100, y: 500, width: 400, height: 300), "上方副屏不应使用本屏高度翻转全局坐标")
        precondition(WindowTarget.localRect(quartzFrame: CGRect(x: 2000, y: 0, width: 100, height: 100), screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), primaryTop: 900) == nil, "屏外窗口不能高亮")
        let front = WindowTarget(id: 1, ownerPID: 10, rect: CGRect(x: 100, y: 100, width: 100, height: 100))
        let back = WindowTarget(id: 2, ownerPID: 20, rect: CGRect(x: 0, y: 0, width: 300, height: 300))
        precondition(WindowTarget.hit(CGPoint(x: 150, y: 150), in: [front, back]) == front, "重叠窗口命中最前目标")
        print("通过：截图坐标、控制点、取色、窗口坐标和前后命中")
    }
}
