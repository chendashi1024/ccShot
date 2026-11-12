<p align="center">
  <img src="docs/website-preview/assets/icon.png" width="96" height="96" alt="ccShot 图标">
</p>

<h1 align="center">ccShot</h1>

<p align="center">截完图，直接选字。免费的 macOS 和 Windows 截图、标注与钉图工具。</p>

<p align="center">
  <a href="https://ccshot.app/">官网</a> ·
  <a href="https://github.com/chendashi1024/ccShot/releases/tag/v0.1.3">下载 ccShot</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="https://github.com/chendashi1024/ccShot/issues">问题反馈</a>
</p>

![ccShot 的圆润标注界面示意，显示曲线箭头和常用工具栏](docs/website-preview/assets/arrow.jpg)

## 截图之后，少走几步

- **直接选字**。截图后在图上拖选需要的文字，Mac 按 ⌘C，Windows 按 Ctrl+C。识别在本机完成，离线可用。
- **截图和标注**。支持区域、窗口和当前屏截图。可添加、调整箭头、画框、文字、画笔、遮挡、高亮和序号。
- **桌面钉图**。把截图留在桌面上对照，需要时继续编辑，也能将剪贴板图片钉在桌面。
- **保存**。用系统窗口选择文件夹，支持 PNG、JPG，也可设定默认位置。

基础截图、标注与识字无需账号或 API Key。

## 下载与安装

| 平台 | 下载 v0.1.3 | 运行方式 |
| --- | --- | --- |
| macOS 14 或更新版本，Apple Silicon（M 系列） | [DMG](https://github.com/chendashi1024/ccShot/releases/download/v0.1.3/ccShot-0.1.3-macos-arm64.dmg) | 打开 DMG，把 `ccShot.app` 拖进「应用程序」 |
| Windows x64 | [ZIP](https://github.com/chendashi1024/ccShot/releases/download/v0.1.3/ccShot-0.1.3-windows-x64.zip) | 完整解压到新目录，运行 `ccShot.exe` |

macOS 首次截图时，按提示允许屏幕录制，再重新打开 ccShot。应用采用临时签名。若系统阻止打开，确认来源和 SHA-256 后，可前往「系统设置 → 隐私与安全性」选择「仍要打开」。 [Apple 的打开应用说明](https://support.apple.com/zh-cn/102445)

Windows 的 ZIP 已包含 .NET 桌面运行时、Visual C++ 运行库和离线模型。程序启动后在任务栏通知区域显示图标。程序未签名，若系统提示未知发布者，请先核对下载文件的 SHA-256。 [发布说明与校验文件](https://github.com/chendashi1024/ccShot/releases/tag/v0.1.3)

## 识字原理

两端都在本机处理截图和识别结果，无需联网、登录或提供 API Key。识别完成后，可以在截图编辑窗和钉图上直接拖选文字。

### macOS · Apple 系统 API

1. ccShot 用 ScreenCaptureKit 的 `SCScreenshotManager` 获取截图像素。
2. 截图交给 VisionKit 的 `ImageAnalyzer`，使用 `.text` 配置和简体中文、繁体中文、英语区域设置。这是 Apple 提供的本机图像文字分析能力，模型由系统管理。
3. VisionKit 的 `ImageAnalysisOverlayView` 把分析结果叠在原图上，提供文字命中、拖选和高亮。ccShot 将选中的文字写入系统剪贴板。遮挡标注触发重新分析时，系统 Vision 的 `VNRecognizeTextRequest` 还用于定位需要排除的文字区域。

[Apple VisionKit API](https://developer.apple.com/documentation/visionkit/imageanalyzer) · [截图实现](app/Sources/DisplayCapture.swift) · [选字实现](app/Sources/ImageWindow.swift) · [遮挡处理](app/Sources/SafeTextImage.swift)

### Windows · 随包提供的本地 OCR 模型

1. ccShot 用 Windows GDI 获取截图，再把像素交给内置的 PaddleOCR PP-OCRv4 轻量模型。两个 ONNX 模型由 ONNX Runtime 在本机 CPU 执行。
2. `det.onnx` 找出截图中的文字行。ccShot 按这些区域裁切图像，交给 `rec.onnx` 识别，再用随包字典 `dict.txt` 把模型输出解码成文字。
3. ccShot 根据识别序列的位置估算逐字框，用图像中的间隙补空格，再按阅读顺序组织各行。编辑窗把字框映射回原图，支持拖选一部分文字并复制到 Windows 剪贴板。
4. 模型和运行库都在 ZIP 内，识字无需另行下载。如果模型加载失败，程序会提示，截图、标注、复制图片与保存仍可用。

[OCR 引擎](windows/src/ccShot.Core/Ocr/Paddle/PaddleOcrEngine.cs) · [Windows 选字实现](windows/src/ccShot.Windows/Editor/EditorWindow.cs) · [模型来源与许可](windows/THIRD-PARTY-NOTICES.md)

## 常用操作

### macOS

| 操作 | 默认方式 |
| --- | --- |
| 开始截图 | F1，或从菜单栏进入。如果 F1 调节亮度，可试 Fn+F1，默认备用键为 ⌃⌥S |
| 复制 | ⌘C 复制当前选中文字或图片，保留编辑窗 |
| 撤销 / 重做 | ⌘Z / ⌘⇧Z；兼容 Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y |
| 调整标注 | 拖框内部或箭头线身移动，拖控制点调整；Delete 删除，方向键微调 |
| 连续绘制 | 空白处继续画；在已有同类标注上另画，按住 Option 拖动 |
| 完成 | Return、点「完成」，或用选择工具双击截图内的空白处，复制后关闭编辑窗 |
| 钉图 | F3，或从菜单栏选择「钉住剪贴板」 |

### Windows

默认按 `Ctrl+Alt+X` 开始框选。编辑时用 `Ctrl+C` 复制选中的文字或图片，用 `Ctrl+Shift+C` 复制全部可选文字。更多操作见 [Windows 使用说明](windows/docs/使用说明.txt)。

更新时先退出 ccShot。Mac 替换「应用程序」里的旧版，Windows 将新版 ZIP 解压到新目录后运行。 [macOS 升级与权限说明](docs/发布流程.md#release-升级说明) · [所有版本](https://github.com/chendashi1024/ccShot/releases)

## 从源码构建

macOS 需要 Apple Silicon Mac 和 Xcode 命令行工具。原生 App 使用 Swift、AppKit、ScreenCaptureKit 和 VisionKit。

```bash
bash app/build.sh
bash app/install-local.sh
bash app/check.sh --core-only
```

本地安装脚本先核对新旧应用的签名身份。匹配时保留已有屏幕录制授权记录，身份变更时清理旧记录，由用户为新版重新授权。固定本机签名的配置方法见[开发说明](app/README.md#本机固定签名)。

Windows 使用 C#、WPF 和 .NET 8。构建、离线模型与打包步骤见 [Windows 开发说明](windows/README.md)。 [macOS 开发说明](app/README.md) · [贡献指南](CONTRIBUTING.md) · [发布流程](docs/发布流程.md)

## 许可证

[MIT](LICENSE)
