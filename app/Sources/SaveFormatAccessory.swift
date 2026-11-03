import AppKit
import UniformTypeIdentifiers

@MainActor final class SaveFormatAccessory: NSView {
    private weak var panel: NSSavePanel?
    let picker = NSPopUpButton()
    private let hint = NSTextField(labelWithString:"透明区域会填为白色")
    var type: UTType { picker.indexOfSelectedItem == 1 ? .jpeg : .png }

    init(panel: NSSavePanel) {
        self.panel = panel
        super.init(frame:CGRect(x:0,y:0,width:300,height:66))
        let title = NSTextField(labelWithString:"格式")
        title.frame = CGRect(x:0,y:34,width:44,height:22)
        picker.frame = CGRect(x:48,y:30,width:244,height:28)
        picker.addItems(withTitles:["PNG","JPG"])
        picker.setAccessibilityLabel("图片格式")
        picker.target = self; picker.action = #selector(changeFormat)
        hint.frame = CGRect(x:52,y:3,width:244,height:22)
        addSubview(title); addSubview(picker); addSubview(hint)
        changeFormat()
    }
    required init?(coder: NSCoder) { fatalError("不支持归档初始化") }
    @objc func changeFormat() {
        guard let panel else { return }
        let current = panel.nameFieldStringValue as NSString
        let suffix = current.pathExtension.lowercased()
        let stem = ["png","jpg","jpeg"].contains(suffix) ? current.deletingPathExtension : current as String
        panel.nameFieldStringValue = stem + (type == .jpeg ? ".jpg" : ".png")
        panel.allowedContentTypes = [type]
        hint.isHidden = type != .jpeg
    }
}
