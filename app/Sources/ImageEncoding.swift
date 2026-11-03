import AppKit
import UniformTypeIdentifiers

// 预览、复制和保存共用同一份合成图；编码不包含选框或工具栏。
enum ImageEncoding {
    static func data(_ image: CGImage, type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
