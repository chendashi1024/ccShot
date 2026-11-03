# CcShot 原生开发底座

最低构建目标 macOS 14、arm64；目前只在 macOS 15.4.1 本机验证。使用已有 Xcode，无第三方依赖；构建生成本地 ad-hoc 签名的 `build/CcShot.app`，不安装到 Applications。

```bash
bash build.sh
open build/CcShot.app
```

菜单栏 CcShot → 区域截图。F1、Control+Option+S 注册为截图键，F3 在当前截图中钉图，否则钉剪贴板；实体全局快捷键仍待验证，不把注册成功视为可用。没有屏幕录制授权时仅提示，不申请或更改权限。

当前路径：当前屏快照 → 拖出矩形（可拖动八个控制点、移动及按方向键 1 px/Shift 10 px 微调，⌘A 全屏）→ 完成 → 本地文字识别/复制/PNG或JPG保存/钉图。选区中 ⌘C、⌘S、F3 直接处理该选区，不读旧编辑窗。编辑窗复制图后关闭；复制文字保留。钉图置顶、可移动/缩放、可调查看透明度；导出使用源像素，不使用预览图。

受控界面演示（仅虚构样本，不截桌面）：

```bash
build/CcShot.app/Contents/MacOS/CcShot --fixture "$PWD/../prototype/local-ocr/results/2026-11-03-native-01/fixtures/01-01.png"
```

增加 `--select` 可在屏幕上铺开虚构样本测试框选。它不是屏幕截图的性能或多屏证据。

```bash
bash check.sh
```

检查范围：裁剪坐标、边缘及无效区域、像素和可见框往返；真实 NSView 选择回调裁图；PNG/JPG 编解码尺寸、剪贴板 PNG 写入、两个独立窗口、钉图置顶、复制只关闭编辑窗及关闭后移出窗口管理列表。剪贴板测试恢复此前内容，不把原内容写入证据。

2026-11-03：上述自动检查通过，真实开发版窗口已通过 CUA 打开检查，样本识别完成、按钮可见。鼠标框选全流程、保存对话框、真实全局按键、权限恢复和混合多屏尚未通过完整验收。设置、完整标注、美化、云 AI 与发布仍未完成；44 项范围继续保留。这是开发底座，不是完整本地体验版。


## 选区交互（2026-11-03）

已接入八个控制点（含跨过固定边反向调整）、指针旁放大镜、原图 sRGB 取色。C 复制 HEX，Shift+C 复制 RGB；无有效像素时不写旧色值。Esc 在拖动中先恢复原选区，之后清空选区，再退出。已保存的像素边界直接用于输出，避免反复换算扩大裁剪范围。

新增检查包括八控制点的屏边限制、机器精度边界、已知红绿蓝像素、视图的缩放/取消事件以及 C/Shift+C 到剪贴板。它们是直接调用本视图事件处理的受控回归，不代表实体鼠标/键盘和多屏已通过。

[原生视图渲染预览](previews/selection-controls-2026-11-03.png)使用自制样本，由真实 AppKit 画布绘制并检查控制点、贴边放大镜、像素标尺和操作条；它不是真实桌面捕获。可用 `--fixture <样本> --render-selection <PNG路径>` 重现，不读取桌面内容。


## 窗口捕获（2026-11-03）

未框选时按前后顺序高亮可捕获窗口，单击捕获该窗口，拖动继续区域截图。捕获前重新校验窗口 ID 与所属进程，已消失或身份不符则拒绝，原选区界面仍可继续使用。窗口输出默认不含阴影，完整窗口可能包含屏幕上被其他窗口遮住的部分，这是 [Apple 单窗口过滤器](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)) 的行为。原生像素按过滤器的 [pointPixelScale](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/pointpixelscale) 计算。

已用现有权限真实捕获本进程的虚构样本窗口，并拒绝已关闭窗口和错误进程；未申请新权限。[真实受控截图](previews/window-capture-2026-11-03.png)及[高亮渲染预览](previews/window-highlight-2026-11-03.png)均已查看。这不代表第三方窗口的完整鼠标流程或多屏全部通过。

可用 `--fixture <样本> --window-smoke-test <报告.json>` 复现本进程窗口捕获；无既有屏幕录制授权时跳过并返回 2，不请求权限。`--render-window-highlight <PNG路径>` 仅渲染虚构样本高亮。
