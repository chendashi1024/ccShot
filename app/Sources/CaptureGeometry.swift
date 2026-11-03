import AppKit

enum CaptureGeometry {
    static func pixelRect(_ selection: CGRect, canvas: CGSize, image: CGSize) -> CGRect? {
        guard [canvas.width, canvas.height, image.width, image.height].allSatisfy({ $0.isFinite && $0 > 0 }),
              [selection.origin.x, selection.origin.y, selection.width, selection.height].allSatisfy({ $0.isFinite }) else { return nil }
        let rect = selection.standardized.intersection(CGRect(origin: .zero, size: canvas))
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let x = floor(rect.minX * image.width / canvas.width)
        let y = floor((canvas.height - rect.maxY) * image.height / canvas.height)
        let right = min(image.width, ceil(rect.maxX * image.width / canvas.width))
        let bottom = min(image.height, ceil((canvas.height - rect.minY) * image.height / canvas.height))
        return CGRect(x: max(0, x), y: max(0, y), width: right - max(0, x), height: bottom - max(0, y))
    }

    // 框线展示与最终裁剪共用像素边界，避免悄悄输出选框外的内容。
    static func viewRect(_ pixels: CGRect, canvas: CGSize, image: CGSize) -> CGRect {
        CGRect(x: pixels.minX * canvas.width / image.width,
               y: canvas.height - pixels.maxY * canvas.height / image.height,
               width: pixels.width * canvas.width / image.width,
               height: pixels.height * canvas.height / image.height)
    }
}
