import AppKit
import VisionKit
import UniformTypeIdentifiers

@MainActor final class ImageWindow: NSWindowController, NSWindowDelegate, ImageAnalysisOverlayViewDelegate {
    let image: CGImage
    let pinned: Bool
    private let imageView = NSImageView()
    private let overlay = ImageAnalysisOverlayView()
    private let status = NSTextField(labelWithString: "正在识别文字…")
    private var recognition: Task<Void, Never>?
    private var closed = false
    var onClose: (() -> Void)?
    var onPin: ((CGImage) -> Void)?

    init(image: CGImage, pinned: Bool) {
        self.image = image
        self.pinned = pinned
        let ratio = CGFloat(image.height) / CGFloat(image.width)
        let width = min(900, max(pinned ? 580 : 420, CGFloat(image.width)))
        let height = min(700, max(300, width * ratio + 95))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = pinned ? "CcShot · 钉图" : "CcShot · 开发版"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: pinned ? 580 : 420, height: 260)
        if pinned { window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] }
        super.init(window: window)
        window.delegate = self
        let root = NSView()
        window.contentView = root
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        overlay.delegate = self
        overlay.trackingImageView = imageView
        overlay.preferredInteractionTypes = .textSelection
        overlay.autoresizingMask = [.width, .height]
        imageView.addSubview(overlay)
        let toolbar = NSStackView()
        toolbar.spacing = 8
        let buttons: [(String, Selector)] = [("复制图片", #selector(copyImage)), ("保存", #selector(saveImage)), ("复制全部文字", #selector(copyAllText))]
        for (title, selector) in buttons { toolbar.addArrangedSubview(makeButton(title, selector)) }
        if !pinned { toolbar.addArrangedSubview(makeButton("钉图", #selector(pinImage))) }
        else {
            let label = NSTextField(labelWithString: "透明度")
            toolbar.addArrangedSubview(label)
            let opacity = NSSlider(value: 1, minValue: 0.2, maxValue: 1, target: self, action: #selector(changeOpacity(_:)))
            opacity.widthAnchor.constraint(equalToConstant: 80).isActive = true
            toolbar.addArrangedSubview(opacity)
        }
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [toolbar, imageView, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        overlay.frame = imageView.bounds
        overlay.setContentsRectNeedsUpdate()
        recognition = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var config = ImageAnalyzer.Configuration(.text)
                config.locales = ["zh-Hans", "zh-Hant", "en-US"]
                let result = try await ImageAnalyzer().analyze(image, orientation: .up, configuration: config)
                guard !Task.isCancelled, !closed else { return }
                overlay.analysis = result
                overlay.setContentsRectNeedsUpdate()
                status.stringValue = result.transcript.isEmpty ? "没有发现文字" : "拖选文字后 ⌘C 复制 · \(image.width) × \(image.height) px"
            } catch {
                guard !closed, !Task.isCancelled else { return }
                status.stringValue = "文字识别失败，仍可复制或保存图片"
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
    @objc func copy(_ sender: Any?) {
        let selected = overlay.selectedText
        if !selected.isEmpty { writeText(selected) }
        else { copyImage() }
    }
    override func selectAll(_ sender: Any?) {
        let text = overlay.text
        guard !text.isEmpty else { return }
        overlay.selectedRanges = [text.startIndex..<text.endIndex]
    }
    @objc func copyImage() {
        guard let png = Self.encoded(image, type: .png) else { status.stringValue = "图片编码失败"; return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { status.stringValue = "复制失败，请重试"; return }
        status.stringValue = "图片已复制"
        if !pinned { close() }
    }
    @objc func copyAllText() {
        let text = overlay.text
        guard !text.isEmpty else { status.stringValue = "当前没有可复制文字"; return }
        writeText(text)
    }
    private func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        status.stringValue = pasteboard.setString(text, forType: .string) ? "文字已复制" : "复制失败，请重试"
    }
    @objc func saveDocument(_ sender: Any?) { saveImage() }
    @objc func saveImage() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "CcShot-\(Int(Date().timeIntervalSince1970)).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
            guard let data = Self.encoded(self.image, type: type) else { self.status.stringValue = "图片编码失败"; return }
            do { try data.write(to: url, options: .atomic); self.status.stringValue = "图片已保存" }
            catch { self.status.stringValue = "保存失败，请检查目录权限与可用空间" }
        }
    }
    static func encoded(_ image: CGImage, type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
    @objc private func pinImage() { onPin?(image) }
    @objc private func changeOpacity(_ sender: NSSlider) { window?.alphaValue = sender.doubleValue }
    override func cancelOperation(_ sender: Any?) {
        if overlay.hasActiveTextSelection { overlay.resetSelection() } else { close() }
    }
    func windowWillClose(_ notification: Notification) {
        closed = true; recognition?.cancel(); recognition = nil; overlay.analysis = nil
        onClose?()
    }
}
