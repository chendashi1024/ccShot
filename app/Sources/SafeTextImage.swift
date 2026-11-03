import AppKit
import Vision

// 原图识别只提供内存中的几何位置，不将其原文交给复制或网络消费者。
enum SafeTextImage {
    enum PreparationError: Error { case allocation, unavailableGeometry }
    static func textRegions(in image: CGImage) throws -> [CGRect] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).map { value in
            let box = value.boundingBox
            return CGRect(x: box.minX * CGFloat(image.width), y: box.minY * CGFloat(image.height), width: box.width * CGFloat(image.width), height: box.height * CGFloat(image.height))
        }
    }
    static func regionsToSuppress(textRegions: [CGRect], occlusions: [CGRect], size: CGSize) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: size)
        return textRegions.compactMap { region in
            let padded = region.insetBy(dx: -3, dy: -3).intersection(bounds)
            return occlusions.contains(where: { $0.intersects(padded) }) ? padded : nil
        }
    }
    static func prepare(image: CGImage, baseRegions: [CGRect], occlusions: [CGRect]) throws -> CGImage {
        guard !occlusions.isEmpty else { return image }
        let currentRegions = try textRegions(in: image)
        let size = CGSize(width: image.width, height: image.height)
        let blocked = regionsToSuppress(textRegions: baseRegions + currentRegions, occlusions: occlusions, size: size)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PreparationError.allocation }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.white.cgColor)
        for region in blocked { context.fill(region.integral) }
        try Task.checkCancellation()
        guard let safe = context.makeImage() else { throw PreparationError.allocation }
        return safe
    }
}
