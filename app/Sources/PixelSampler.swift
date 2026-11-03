import AppKit

struct SampledColor: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var rgb: String { "RGB(\(red), \(green), \(blue))" }
}

enum PixelSampler {
    static func color(in image: CGImage, x: Int, y: Int) -> SampledColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var components = [UInt8](repeating: 0, count: 4)
        let rendered = components.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        let alpha = Int(components[3])
        func channel(_ value: UInt8) -> UInt8 { alpha == 0 ? 0 : UInt8(min(255, (Int(value) * 255 + alpha / 2) / alpha)) }
        return SampledColor(red: channel(components[0]), green: channel(components[1]), blue: channel(components[2]))
    }
}
