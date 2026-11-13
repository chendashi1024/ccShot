# ccShot 官网发布

在本机打开 ccShot 仓库，用 Codex 的 Cloudflare 插件发送「发布 ccShot 官网」。正式域名为 [ccshot.app](https://ccshot.app/)，部署到现有 Worker `ccshot-site`。

## 发布源

- `website/public/` 存放正式首页和静态文件。下载与 GitHub 跳转在 `website/src/index.js`。
- 安装包与对应的 `.sha256` 存放于 R2 存储桶 `ccshot-downloads`，公开下载域名为 `download.ccshot.app`。更新版本时先上传并校验两个平台的文件，再更新和发布官网入口。
- 改过静态文件后重新生成清单，然后运行测试。清单工具需要 Python 3 和 `blake3`，测试和本机上传使用 Node.js 22 或更新版本。

```bash
python3 website/deploy/make-manifest.py
node --test website/test/*.js
```

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
