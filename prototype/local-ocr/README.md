# CcShot 本地 OCR 技术原型

不是完整App或正式视觉稿。Swift/AppKit + Apple VisionKit，macOS14+、Apple Silicon；仅在本机15.4.1验证。无第三方依赖、无云OCR。

## 构建与基准

```bash
bash build.sh
bash run-benchmark.sh
```

需要现有Xcode/命令行工具，不会安装依赖。build目录为本地ad-hoc签名App，不安装到Applications。受限命令沙箱可能无法注册AppKit进程；须在正常桌面会话运行，不改安全设置。

## 打开受控样本

```bash
open build/CcShotPrototype.app --args --fixture "$PWD/results/2026-11-03-native-01/fixtures/01-01.png" --evidence "$PWD/results/2026-11-03-native-01/ui-manual.jsonl"
```

直接拖选图中中文，⌘C或按钮复制。先载入样本，再按“验证样本窗口快照”，只截本App的窗口；该按钮需要已有屏幕录制授权。没有授权只提示，不申请。

不带fixture时快捷键进入当前屏幕截图路径，真实截图只在内存，不写日志正文或图片文件。不要把含私密内容的屏幕图作为测试证据上传或提交。

F1和Control+Option+S已实现注册，但全局回调尚未验收；程序化selectedRanges前4字变5字的边界问题保留为已知失败。鼠标拖选4字、全文复制及实际窗口截图已验证。详见 [TEST-REPORT.md](TEST-REPORT.md)。

`--self-test`会测试选字API并将合成文本写入剪贴板后恢复，日志明确标记失败；不要用于真实用户截图。

## S0 接续诊断

最新结果见 [2026-11-03 排障记录](results/2026-11-03-s0-diagnosis/README.md)。可在自检命令后增加 `--exit-after-self-test`，范围或全文断言失败时返回非零。`--diagnose-keys` 是虚构样本模式下的显式按键诊断，不记录普通输入。
