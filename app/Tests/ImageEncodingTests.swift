import AppKit
import UniformTypeIdentifiers

@main struct ImageEncodingTests {
    static func main() {
        let context = CGContext(data:nil,width:64,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x:32,y:0,width:32,height:32))
        let image = context.makeImage()!
        var checks: [String:Bool] = [:]
        for type in [UTType.png, .jpeg] {
            let data = ImageEncoding.data(image,type:type)!
            let source = CGImageSourceCreateWithData(data as CFData,nil)!
            let decoded = CGImageSourceCreateImageAtIndex(source,0,nil)!
            checks[type.identifier+"_dimensions"] = decoded.width == 64 && decoded.height == 32
            let rgba = CGContext(data:nil,width:64,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            rgba.draw(decoded,in:CGRect(x:0,y:0,width:64,height:32))
            let pixel = rgba.data!.assumingMemoryBound(to:UInt8.self).advanced(by:16*rgba.bytesPerRow+8*4)
            checks[type.identifier+"_transparent_background"] = type == .png ? pixel[3] == 0 : pixel[0] >= 250 && pixel[1] >= 250 && pixel[2] >= 250 && pixel[3] == 255
            let red = rgba.data!.assumingMemoryBound(to:UInt8.self).advanced(by:16*rgba.bytesPerRow+48*4)
            checks[type.identifier+"_opaque_content"] = red[0] > 240 && red[1] < 15 && red[2] < 15
        }
        let result: [String:Any] = ["checks":checks,"passed":checks.values.allSatisfy{$0}]
        print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
        exit(checks.values.allSatisfy{$0} ? 0 : 1)
    }
}
