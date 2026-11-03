# CcShot

> 像 Snipaste 一样快和轻的 Mac 截图工具：截完文字直接能选，一键问你自己的 AI（默认 DeepSeek）。开源、免费、原生。

CcShot 的名字来自作者名字的缩写 "cc" + Shot（截图）。

## 为什么做它

- 截图里的字复制不出来，Snipaste 免费版没有 OCR（文字识别）。
- Snipaste 里箭头、框的粗细和样式藏得深，要找半天。
- 截完想问 AI，要在好几个 App 之间来回切。

## 亮点

1. **截完文字直接可选**：像微信截图、苹果 Live Text 一样，鼠标移到字上就能拖选复制（本地识别，不联网）。
2. **一键问 AI**：按 `⌘J`，把截图和文字发给你自己的模型。用你自己的 Key（BYOK），默认 DeepSeek（便宜），也预设了 GPT、Claude、Gemini、通义千问、Kimi、智谱、OpenRouter，还能自定义。
3. **标注样式一眼能调**：选中工具，粗细、颜色、线型就在工具栏下方展开；滚轮直接调粗细；每个工具记住上次的样式。
4. **F1 秒开截图**：照搬 Snipaste 最好用的一点。
5. **一键美化**（配套功能）：按 `B` 加背景，自动出 1920×1080 等尺寸的图。

## 状态

规划阶段，还没有写代码。第一版（MVP）计划 3 周做完。

## 文档目录

| 文档 | 内容 |
|---|---|
| [docs/PRD.md](docs/PRD.md) | 产品需求：全部功能点、优先级、交互、快捷键、排期、待定问题 |
| [docs/竞品调研.md](docs/竞品调研.md) | 同类产品对比、我们的定位、起名查重 |
| [docs/决策记录.md](docs/决策记录.md) | 已经拍板的决定和理由 |
| [docs/推广计划.md](docs/推广计划.md) | 发布和拿 star 的推广计划 |
| [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) | 给 AI 编程助手（Claude Code 等）的工作说明 |
| docs/技术方案.md | 待 Claude 调研后补上 |
| docs/任务拆解.md | 待 Claude 调研后补上 |

## 安装说明（预告）

CcShot 不做苹果签名公证，只在 GitHub Releases 发 `.dmg` / `.zip`。第一次打开会被系统拦下，处理方法：

- 系统设置 → 隐私与安全性 → 点「仍要打开」；或
- 终端运行：`xattr -dr com.apple.quarantine /Applications/CcShot.app`

## 许可证

暂定 MIT（待最终确认）。


## 当前可运行进度

原生开发底座已进入 [`app/`](app/README.md)，可构建并运行截图、图片输出、钉图与本地选字的初始路径；完整基础功能仍在实现。产品范围和实际验证状态以 [GOALS](GOALS.md) 与 [HANDOFF](HANDOFF.md) 为准，旧简介中的模型默认值不作为当前配置。
