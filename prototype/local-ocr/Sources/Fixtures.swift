import AppKit
import CoreText
import VisionKit

struct Fixture: Codable {
    let id: String
    let category: String
    let condition: String
    let text: String
    let file: String
    let font: String
    let fontSize: Double
    let scale: Int
    let width: Int
    let height: Int
}

enum FixtureFactory {
    // 自写真值，先于识别固定；没有使用用户截图。
    static let passages: [(String, String)] = [
        ("日常中文", "今天下午三点半，我们在图书馆门口见面。\n请带上笔记本电脑，提前检查电量和网络。\n截图里的文字应该可以直接选择、复制。"),
        ("产品说明", "这是一款开源的本地截图工具，不需要注册账号。\n先按快捷键，再选择文字，最后复制到剪贴板。\n图片只在本机处理，识别过程不会上传截图。"),
        ("中英混排", "CcShot 使用 Apple VisionKit 在 Mac 上识别文字。\n打开 README.md，检查 API Key 是否已经填写。\n按 Command + C 复制，版本号为 v0.1.0。"),
        ("数字标点", "订单编号：20261103，合计金额：¥128.50。\n折扣为 15%，联系电话：13800138000。\n日期：2026-11-03；时间：09:30；数量：108。"),
        ("繁体中文", "這是一段繁體中文，測試截圖中的文字辨識。\n請選取需要的句子，複製後貼到筆記軟體。\n檔案儲存在本機，不會傳送到雲端伺服器。"),
        ("代码与路径", "错误提示：FileNotFoundError，找不到指定文件。\n路径：/Users/demo/Documents/report_2026.txt\nif count >= 10: print(\"测试成功\")"),
        ("近形字", "未末、己已巳、日曰、土士、口囗，注意字形差别。\n账户余额为零元，登录密码不要写入运行日志。\n一二三四五六七八九十，壹贰叁肆伍陆柒捌玖拾。"),
        ("中文排版", "“轻和快”不等于功能越少越好。\n《本地文字识别测试》包含中文、英文及标点。\n我们关注：准确率、响应时间，以及真实操作体验。")
    ]

    static func generate(at directory: URL) throws -> [Fixture] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let conditions: [(String, Double, Int, Double, Double)] = [
            ("清晰20pt@2x", 20, 2, 0.08, 1.0),
            ("小字12pt@1x", 12, 1, 0.08, 1.0),
            ("深色16pt@2x", 16, 2, 0.94, 0.08),
            ("低对比12pt@1x", 12, 1, 0.56, 0.72)
        ]
        var fixtures: [Fixture] = []
        for (index, passage) in passages.enumerated() {
            for (conditionIndex, condition) in conditions.enumerated() {
                let (name, size, scale, foreground, background) = condition
                let width = 960 * scale
                let height = 230 * scale
                let id = String(format: "%02d-%02d", index + 1, conditionIndex + 1)
                let fontName = passage.0 == "繁体中文" ? "PingFangTC-Regular" : "PingFangSC-Regular"
                let font = CTFontCreateWithName(fontName as CFString, size * Double(scale), nil)
                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
                let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: colorSpace,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.setFillColor(CGColor(gray: background, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                for (lineIndex, text) in passage.1.components(separatedBy: "\n").enumerated() {
                    let attributes: [NSAttributedString.Key: Any] = [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: foreground, alpha: 1)
                    ]
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                    guard lineWidth < Double(width - 64 * scale) else {
                        throw NSError(domain: "Fixtures", code: 2, userInfo: [NSLocalizedDescriptionKey: "样本可能裁字：\(id)"])
                    }
                    context.textPosition = CGPoint(x: 32 * scale, y: height - (50 + lineIndex * 54) * scale)
                    CTLineDraw(line, context)
                }
                let image = context.makeImage()!
                let path = directory.appendingPathComponent(id + ".png")
                let target = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(target, image, nil)
                guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
                fixtures.append(Fixture(id: id, category: passage.0, condition: name, text: passage.1,
                                        file: id + ".png", font: fontName, fontSize: size,
                                        scale: scale, width: width, height: height))
            }
        }
        let data = try JSONEncoder().encode(fixtures)
        let object = try JSONSerialization.jsonObject(with: data)
        try writeJSON(object, to: directory.appendingPathComponent("manifest.json"))
        return fixtures
    }
}

@MainActor func runBenchmark(fixturesDirectory: URL, output: URL) async throws {
    guard ImageAnalyzer.isSupported else {
        throw NSError(domain: "CcShotPrototype", code: 3, userInfo: [NSLocalizedDescriptionKey: "本机不支持 ImageAnalyzer"])
    }
    let fixtures = try FixtureFactory.generate(at: fixturesDirectory)
    let analyzer = ImageAnalyzer()
    var results: [[String: Any]] = []
    let started = ISO8601DateFormatter().string(from: Date())
    for repetition in 1...3 {
        // 每轮轮换次序；同一引擎、同一配置，保留每一次结果。
        let offset = (repetition - 1) * 7
        let order = Array(fixtures[offset...]) + Array(fixtures[..<offset])
        for fixture in order {
            let image = try readImage(fixturesDirectory.appendingPathComponent(fixture.file))
            let before = ProcessInfo.processInfo.systemUptime
            do {
                let analysis = try await LocalOCR.recognize(image, analyzer: analyzer)
                let ms = (ProcessInfo.processInfo.systemUptime - before) * 1000
                results.append(["id": fixture.id, "repetition": repetition, "text": analysis.transcript,
                                "latency_ms": ms, "error": NSNull()])
                print("\(fixture.id) 第\(repetition)轮 \(Int(ms))ms")
            } catch {
                results.append(["id": fixture.id, "repetition": repetition, "text": "",
                                "latency_ms": (ProcessInfo.processInfo.systemUptime - before) * 1000,
                                "error": error.localizedDescription])
            }
        }
    }
    try writeJSON(["engine": "Apple VisionKit ImageAnalyzer (.text)", "locales": LocalOCR.locales,
                   "supported_languages": ImageAnalyzer.supportedTextRecognitionLanguages,
                   "os": ProcessInfo.processInfo.operatingSystemVersionString,
                   "started_at": started, "finished_at": ISO8601DateFormatter().string(from: Date()),
                   "repetitions": 3, "synthetic_only": true, "results": results], to: output)
}
