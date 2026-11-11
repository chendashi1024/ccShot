# ccShot · Windows 版

Windows 版的目标只有一个：按快捷键框选截图后，直接在图上拖选文字并复制。基础识字用本地
PaddleOCR 模型 + ONNX Runtime 在 CPU 上跑，不需要账号、网络、独立显卡或 API Key。

**当前状态（2026-11-11）**

| 层 | 状态 |
|---|---|
| 代码 | 托盘、全局热键、区域/窗口/当前屏截图、选区调整、原位标注、文字拖选、复制/保存、钉图选字与继续编辑 |
| 构建与测试 | Mac 交叉构建通过，64 项核心测试通过。Windows Server 2025 x64 的构建和同一批 64 项测试也已通过 |
| Windows 桌面 | 在托管 Windows x64 桌面实际唤起、框选、CPU 识字、拖选并回读剪贴板，连续唤起和 Esc 取消、窗口点选、钉图继续编辑、三种遮挡后的剪贴板检查均通过 |
| 试用包 | 依赖系统运行时和自包含的两个本地 ZIP，内置轻量模型。自包含包附 .NET 和桌面组件第三方声明 |
| 待验收 | Windows 11 实机、不同缩放比例的双屏、干净系统覆盖升级和卸载，以及对外发布前的分发核对 |

Windows 的测试结论和首轮历史数据见 [阶段报告](REPORT-2026-11-11.md)。

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
# 依赖 .NET 8 SDK；打包另需 Python 3 和 zip
cd windows
dotnet build -c Release                     # 三个工程 + 测试工程，可在 macOS 上交叉编译
dotnet test tests/CcShot.Core.Tests         # 64 项逻辑测试

./tools/fetch-models.sh mobile              # 下载 PP-OCRv4 轻量模型（14.9 MB）
./tools/package.sh                          # 生成 dist/packages/<commit>/ 下的两个 ZIP

# 在 Windows 上直接运行（需要 .NET 8 Desktop Runtime）
dotnet run --project src/CcShot.Windows -c Release
```

程序启动后只在托盘出现，没有主窗口。默认快捷键 `Ctrl+Alt+X`（可在设置里改，冲突会就地提示）。

## 已实现的功能

- 托盘菜单：区域截图 / 当前屏幕 / 选择窗口 / 设置 / 退出；双击托盘等于区域截图。
- 全局快捷键：`RegisterHotKey` + 隐藏消息窗口，注册失败会告知原因（被占用 / 无法识别）。
- 截图：先冻结屏幕画面，再框选或点选窗口。拖选后可调整选区，按回车或双击确认；Esc 取消。
- 编辑窗口：贴在截图原位置，工具栏按空间贴边避让（下方放不下就放上方）。
- 直接选字：识别结果的每个字符都有独立框（来自识别器 CTC 时间步 + 相邻字符中点划分），可正反拖选、单字、标点、跨行；`Ctrl+C` 复制选中文字，`Ctrl+Shift+C` 复制全部。
- 标注：箭头（可拖中间点拉弯）、方框、椭圆、文字、画笔、遮挡（实心/马赛克/模糊）、高亮、序号；选中后可移动、四角缩放、Delete 删除；`Ctrl+Z`/`Ctrl+Y` 撤销重做（一次手势一步）。
- 输出：复制图片、保存 PNG/JPG、钉图（拖选文字、移动、缩放、保存和继续编辑），托盘可直接钉住剪贴板图片。
- 安全输出：复制/保存/钉图都走同一份合成图；三种遮挡都会立即丢弃原文字结果，重新识别合成图并排除遮挡范围的字符；识别完成前暂停文字输出。
- 设置：只有快捷键与保存位置两项，都就地校验（快捷键冲突、目录不可写）。

## 已知限制

- Windows 托管桌面验证覆盖自制窗口和固定样本。真实双屏的混合缩放、显示器热插拔，以及 Windows 11 实机和普通第三方窗口仍待验收。
- 窗口截图使用选中窗口在冻结桌面上的可见矩形。被其他窗口盖住的部分按屏幕实际显示保留。
- 中英混排、代码的空格和标点仍可能识别有误。模型质量看字符错误率，选择准确率以固定答案为准。
- 首版不包含放大镜取色、钉图透明度、AI 问答、美化、长截图、历史、录屏和自动更新。

## 证据位置

| 内容 | 路径 |
|---|---|
| 同图对比原始数据（10 张带逐字真值的新样本） | `reports/2026-11-11-windows01.json` |
| 同图对比原始数据（复用 macOS 原型的 32 张样本） | `reports/2026-11-11-native01.json` |
| 控制台日志（逐图 CER / 耗时） | `reports/2026-11-11-*.log` |
| 阶段报告（含 WIN-01–WIN-07 状态） | `REPORT-2026-11-11.md` |
| 模型与哈希 | `models/models.lock.json` |
| 许可核对 | `THIRD-PARTY-NOTICES.md` |

## Windows 桌面验证

准备 `windows/models/mobile` 后，在隔离的 Windows 桌面从仓库根目录运行以下命令。验证程序会移动鼠标、按快捷键、改写剪贴板和读取自制窗口像素。

```powershell
dotnet build windows/tests/CcShot.Windows.Smoke -c Release
$out = 'windows/tests/CcShot.Windows.Smoke/bin/Release/net8.0-windows'
New-Item -ItemType Directory -Force "$out/models" | Out-Null
Copy-Item -Recurse windows/models/mobile "$out/models"
& "$out/CcShot.Windows.Smoke.exe" windows/testdata/windows-01/01-en.png
```

## 复现 OCR 对比

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
