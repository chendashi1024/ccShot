import AppKit
import VisionKit

enum LocalOCR {
    static let locales = ["zh-Hans", "zh-Hant", "en-US"]
    static func recognize(_ image: CGImage, analyzer: ImageAnalyzer) async throws -> ImageAnalysis {
        var config = ImageAnalyzer.Configuration(.text)
        config.locales = locales
        return try await analyzer.analyze(image, orientation: .up, configuration: config)
    }
}

func readImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "CcShotPrototype", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "无法读取图片：\(url.lastPathComponent)"])
    }
    return image
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url, options: .atomic)
}
