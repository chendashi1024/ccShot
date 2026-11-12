# 第三方组件与许可（Windows 版）

核对日期：2026-11-11。只记录本次实际下载、实际打包的资产；没有核实的项标为待确认，不作为可分发依据。

## 随包分发的资产

| 资产 | 版本 / 文件 | 来源 | 许可 | 原文位置 |
|---|---|---|---|---|
| PP-OCRv4 检测模型（轻量） | `models/mobile/det.onnx`，4 745 517 字节，SHA-256 `d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9` | PaddleOCR 训练权重，经 RapidOCR 项目转为 ONNX，托管于 huggingface.co/SWHL/RapidOCR（`PP-OCRv4/ch_PP-OCRv4_det_infer.onnx`） | Apache-2.0（模型仓库 card 声明 `license: apache-2.0`） | `LICENSES/paddleocr-LICENSE.txt`、`LICENSES/rapidocr-LICENSE.txt` |
| PP-OCRv4 识别模型（轻量） | `models/mobile/rec.onnx`，10 857 958 字节，SHA-256 `48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b` | 同上（`PP-OCRv4/ch_PP-OCRv4_rec_infer.onnx`） | Apache-2.0 | 同上 |
| 识别字典 | `models/mobile/dict.txt`，26 250 字节，6623 条，SHA-256 `a1c84d9bdb9ab29043c58896224d32941783eb821629618416dcb08f12886492` | PaddleOCR 仓库 `ppocr/utils/ppocr_keys_v1.txt` | Apache-2.0 | 同上 |
| ONNX Runtime | `Microsoft.ML.OnnxRuntime` 1.20.1（NuGet） | Microsoft | MIT | `LICENSES/onnxruntime-LICENSE.txt`、`LICENSES/onnxruntime-third-party-notices.txt` |
| Visual C++ x64 运行库（两个 ZIP 内含） | Visual Studio 2022 Redist 组件 `14.44.35211` 中的四个 `Microsoft.VC143.CRT` DLL | [微软官方组件和 SHA-256](tools/vc-runtime.lock.json) | [微软可再分发代码条款](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) | `LICENSES/msvc-runtime-NOTICE.txt` |
| .NET 8 运行时（自包含包内含） | 8.0.34（自包含打包时校验） | Microsoft | MIT | `LICENSES/Microsoft.NETCore.App.Runtime.win-x64-LICENSE.txt`、`LICENSES/Microsoft.NETCore.App.Runtime.win-x64-THIRD-PARTY-NOTICES.txt` |
| Windows Desktop（WPF / WinForms，自包含包内含） | 8.0.34 | Microsoft | MIT | `LICENSES/Microsoft.WindowsDesktop.App.Runtime.win-x64-LICENSE.txt`、`LICENSES/wpf-THIRD-PARTY-NOTICES.txt`、`LICENSES/winforms-THIRD-PARTY-NOTICES.txt` |

WPF 和 WinForms 的声明按实际运行时版本附带。 [WPF v8.0.34 声明](https://github.com/dotnet/wpf/blob/v8.0.34/THIRD-PARTY-NOTICES.TXT) · [WinForms v8.0.34 声明](https://github.com/dotnet/winforms/blob/v8.0.34/THIRD-PARTY-NOTICES.TXT)

可选的精度优先组合 `models/server`（`ch_PP-OCRv4_det_server_infer.onnx` 113 352 104 字节、`ch_PP-OCRv4_rec_server_infer.onnx` 90 530 732 字节）来源和许可同上；本次**没有**打进试用包，只用于同图对比。

## 只在开发工具中使用、不随包分发

| 组件 | 版本 | 用途 | 许可 |
|---|---|---|---|
| StbImageSharp | 2.30.15 | 仅 `CcShot.Tools` 读取基准样本 PNG | 见 [上游许可](https://github.com/StbSharp/StbImageSharp#license) |
| xUnit / Microsoft.NET.Test.Sdk | 2.9.2 / 17.11.1 | 仅测试 | Apache-2.0 / MIT |

分发前可用 `dotnet list package --include-transitive src/CcShot.Windows` 复核随包依赖，确认与应用实际引用一致。

## 待补 / 未确认

1. **模型对外分发复核。** 模型托管页标注 Apache-2.0，打包校验权重哈希并附上游许可。发布前仍需核对随包具体权重的来源声明和附加条件。 [RapidOCR 模型卡](https://huggingface.co/SWHL/RapidOCR)
2. **图标。** `Assets/ccshot.ico` 由仓库内 `app/Resources/AppIcon.icns` 转换，属项目自有资产。
