# ccShot · Windows 版

Windows 版的目标只有一个：按快捷键框选截图后，直接在图上拖选文字并复制。基础识字用本地
PaddleOCR 模型 + ONNX Runtime 在 CPU 上跑，不需要账号、网络、独立显卡或 API Key。

**当前状态（2026-11-11）：**

| 层 | 状态 |
|---|---|
| 代码 | 已实现：托盘与全局快捷键、区域/窗口/当前屏截图、原位编辑窗口、七类标注、文字拖选与复制、复制/保存/钉图、设置 |
| 构建 | 已在 macOS 上交叉编译通过（`dotnet build` / `dotnet publish -r win-x64`，0 错误）；Windows 本机构建未执行 |
| 逻辑实测 | 58 项单元测试在 macOS 上通过（坐标、拖选、撤销、遮挡失效、设置、图像效果、字墨分析） |
| OCR 实测 | 在 macOS（Apple M4）上跑完两套模型 × 两组样本，原始数据见 `reports/` |
| 打包 | 已生成 framework-dependent 与 self-contained 两个 ZIP（未签名、未上传、未公开发布） |
| **Windows 真机运行** | **未执行**：本机没有 Windows 设备或虚拟机，热键、屏幕捕获、DPI、剪贴板、安装升级均未在 Windows 上验证 |

因此：**不要把这一版当作“已验证可发布”**。它是一份可复核、可继续接手的第一版实现。

## 目录结构

```
windows/
  CcShot.sln
  src/CcShot.Core/        跨平台逻辑（几何、OCR 引擎、逐字选择、标注模型、会话与安全输出、设置）
  src/CcShot.Windows/     WPF 应用（纯 C# 构建界面，不用 XAML；WinForms 仅用于托盘图标）
  src/CcShot.Tools/       离线工具：同图 OCR 基准、单图 dump
  tests/CcShot.Core.Tests/ xUnit 测试（可在 macOS/Linux 上跑）
  testdata/windows-01/    新增样本：纯英文/代码/小字/低对比/标点/密集，带逐字真值
  tools/fetch-models.sh   下载模型并打印 SHA-256
  tools/gen_windows_fixtures.py  生成带逐字真值的样本
  tools/package.sh        构建并打出预览包
  models/                 模型存放处（不提交，见 models/README.md）
  reports/                基准原始数据与日志
  docs/使用说明.txt        打进包里的用户说明
  THIRD-PARTY-NOTICES.md  第三方许可核对
```

## 构建与运行

```bash
# 依赖 .NET 8 SDK
cd windows
dotnet build -c Release                     # 三个工程 + 测试工程，可在 macOS 上交叉编译
dotnet test tests/CcShot.Core.Tests         # 58 项逻辑测试

./tools/fetch-models.sh mobile              # 下载 PP-OCRv4 轻量模型（14.9 MB）
./tools/package.sh                          # 生成 dist/packages/<commit>/ 下的两个 ZIP

# 在 Windows 上直接运行（需要 .NET 8 Desktop Runtime）
dotnet run --project src/CcShot.Windows -c Release
```

程序启动后只在托盘出现，没有主窗口。默认快捷键 `Ctrl+Alt+X`（可在设置里改，冲突会就地提示）。

## 已实现的功能

- 托盘菜单：区域截图 / 当前屏幕 / 选择窗口 / 设置 / 退出；双击托盘等于区域截图。
- 全局快捷键：`RegisterHotKey` + 隐藏消息窗口，注册失败会告知原因（被占用 / 无法识别）。
- 截图：先整屏 BitBlt 到内存，再显示遮罩，因此遮罩不会进图、也没有确认后的闪烁；支持多显示器（含负坐标）与逐显示器 DPI。
- 编辑窗口：贴在截图原位置，工具栏按空间贴边避让（下方放不下就放上方）。
- 直接选字：识别结果的每个字符都有独立框（来自识别器 CTC 时间步 + 相邻字符中点划分），可正反拖选、单字、标点、跨行；`Ctrl+C` 复制选中文字，`Ctrl+Shift+C` 复制全部。
- 标注：箭头（可拖中间点拉弯）、方框、椭圆、文字、画笔、遮挡（实心/马赛克/模糊）、高亮、序号；选中后可移动、四角缩放、Delete 删除；`Ctrl+Z`/`Ctrl+Y` 撤销重做（一次手势一步）。
- 输出：复制图片、保存 PNG/JPG、钉图（拖动、滚轮缩放、Esc 关闭、右键复制或保存）。
- 安全输出：复制/保存/钉图都走同一份合成图；裁剪或加遮挡后旧识别结果作废，并自动对合成图重新识别；剪贴板文字只在识别结果与当前图片版本一致时才写入。
- 设置：只有快捷键与保存位置两项，都就地校验（快捷键冲突、目录不可写）。

## 尚未实现或未验证

- 未在 Windows 上运行过：热键真实触发、BitBlt 截图、PerMonitorV2 下的窗口定位、剪贴板、托盘行为都缺 Windows 证据。
- 混合缩放多屏、显示器热插拔、跨屏拖选未测（`MonitorLayout` 有单元测试，不等于真机）。
- 窗口截图用的是“鼠标位置取窗口句柄 + DWM 可见边界”，第三方应用（尤其 UWP、浏览器子窗口）未实测。
- 编辑窗口没有放大镜取色、没有透明度调整、没有钉图的“进入编辑”。
- AI 问答、美化、长截图、历史、录屏、自动更新不在本版范围。
- 代码类文本的半角括号可能被识别成全角；空格靠像素空隙补偿，个别情况仍会缺。

## 证据位置

| 内容 | 路径 |
|---|---|
| 同图对比原始数据（10 张带逐字真值的新样本） | `reports/2026-11-11-windows01.json` |
| 同图对比原始数据（复用 macOS 原型的 32 张样本） | `reports/2026-11-11-native01.json` |
| 控制台日志（逐图 CER / 耗时） | `reports/2026-11-11-*.log` |
| 阶段报告（含 WIN-01–WIN-07 状态） | `REPORT-2026-11-11.md` |
| 模型与哈希 | `models/models.lock.json` |
| 许可核对 | `THIRD-PARTY-NOTICES.md` |

## 复现方式

```bash
cd windows
./tools/fetch-models.sh                       # 模型哈希必须与 models.lock.json 一致
python3 tools/gen_windows_fixtures.py         # 需要 Pillow；生成 testdata/windows-01
cd src/CcShot.Tools
dotnet run -c Release -- bench \
  --manifest ../../testdata/windows-01/manifest.json \
  --fixtures ../../testdata/windows-01 \
  --out ../../reports/retest.json \
  --model mobile=../../models/mobile --model accurate=../../models/server --repeat 3
```

基准工具会输出每张图的识别文本、CER（忽略空格 / 保留空白两种）、逐字框命中率、单字与整行拖选正确率、
检测与识别耗时，以及模型文件体积。
