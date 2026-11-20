# ccShot 官网发布

在本机打开 ccShot 仓库，用 Codex 的 Cloudflare 插件发送「发布 ccShot 官网」。正式域名为 [ccshot.app](https://ccshot.app/)，部署到现有 Worker `ccshot-site`。

## 发布源

- `website/public/` 存放正式首页和静态文件。下载与 GitHub 跳转在 `website/src/index.js`。
- 安装包与对应的 `.sha256` 存放于 R2 存储桶 `ccshot-downloads`，公开下载域名为 `download.ccshot.app`。更新版本时先上传并校验两个平台的文件，再更新和发布官网入口。
- 改过静态文件后重新生成清单，然后运行测试。清单工具需要 Python 3 和 `blake3`，测试和本机上传使用 Node.js 22 或更新版本。

```bash
python3 docs/website-preview/build.py
python3 website/deploy/make-manifest.py
node --test website/test/*.js
```

首页与离线页由 `docs/website-preview/preview.html` 和 `head.html` 共同生成；FAQ 的 JSON-LD 从可见问答提取。`website/public/llms.txt` 是公开产品资料索引，版本更新时与首页、README 一起核对，不代表搜索或 AI 引用保证。首页通过 `rel="alternate"` 引用它；`robots.txt` 已允许抓取全站，sitemap 继续列规范首页，不把资料副本与图标当作独立落地页。

站点图标来自现有 `app/Resources/AppIcon.icns`。需要重新生成时运行 `python3 website/deploy/make-icons.py`（需要 Pillow），再生成清单。`favicon.ico` 包含 16/32/48/64/128/256 像素，MIME 为 `image/vnd.microsoft.icon`；另有 180 像素 `apple-touch-icon.png` 和 192 像素 `icon-192.png`，MIME 均为 `image/png`。原 `/icon.png` 的 URL 与内容保持不变。新图标均独立存放，不内嵌到 HTML。

发布后检查首页、图标、`llms.txt` 的状态码与 Content-Type，确认 Googlebot 和 Googlebot-Image 不受阻挡。再通过 Google Search Console 的网址检查请求重新抓取首页，在 Bing Webmaster Tools 提交首页，并检查 sitemap 状态。图标通过首页声明被重新发现，不能承诺立即更换；参见 [Google 图标规范](https://developers.google.com/search/docs/appearance/favicon-in-search)。

## 从本机发布

1. 在 Cloudflare 插件中查找 `ccshot.app` 的绑定，核对 Worker 名称和当前部署版本，记录版本 ID 供回滚。以下 Worker 接口均位于 `/accounts/{account_id}/workers/scripts/ccshot-site` 下。
2. 通过插件将 `website/deploy/manifest.json` 提交到 `POST /assets-upload-session`。把返回的 `result` 对象通过标准输入传给本机的 `node website/deploy/upload-assets.mjs <account_id>`。脚本用临时上传凭据传送所需文件，并返回上传完成凭据。会话数据只在进程间传递。
3. 通过插件调用 `POST /versions`。把完成凭据填入内存中 `website/deploy/metadata.json` 的 `assets.jwt`，以 JSON 形式上传到 multipart 的 `metadata` 字段。将 `website/src/index.js` 作为 `index.js` 模块上传。可在版本备注中记录对应的 Git 提交。
4. 确认现网版本仍是第 1 步记录的版本，再通过 `POST /deployments` 将新版本流量设为 100%。请求体使用 `strategy: "percentage"` 和 `versions: [{ "version_id": "<新版本 ID>", "percentage": 100 }]`。如需回滚，用同一接口把流量切回第 1 步的版本。

静态资源由 Cloudflare 直接返回，`/go/*` 由 Worker 处理。部署沿用现有域名绑定，点击跳转可直接使用。

## 正式站验收

- 打开 [首页](https://ccshot.app/)，核对页面和图标，检查样式切换与图片放大。
- 从官网的 `/go/download` 和 `/go/download?platform=windows` 分别下载 Mac DMG 与 Windows x64 ZIP。确认最终域名是 `download.ccshot.app`，并与同域的 `.sha256` 校验文件比对。旧的 `source=github` 下载链接也转到同一下载域名。
- `/go/github?to=repo` 跳到 GitHub 仓库，`/go/github?to=release` 跳到对应版本的安装说明。

官网展示版本与仓库根目录的 [VERSION](../VERSION) 对齐。 [安装与发布说明](https://github.com/chendashi1024/ccShot/releases)
