# ccShot 官网发布

在本机打开 ccShot 仓库，用 Codex 的 Cloudflare 插件发送「发布 ccShot 官网」。正式域名为 [ccshot.app](https://ccshot.app/)，部署到现有 Worker `ccshot-site`。

## 发布源

- `website/public/` 存放正式首页和静态文件。下载与 GitHub 跳转在 `website/src/index.js`。
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

- 打开 [首页](https://ccshot.app/)，核对页面、图标和选字实拍，检查样式切换与图片放大。
- 主下载 `/go/download` 和旧链接 `/go/download?source=github` 都应返回同一份 GitHub Release 安装包。实际下载后核对文件大小和 SHA-256。
- `/go/github?to=repo` 跳到 GitHub 仓库，`/go/github?to=release` 跳到对应版本的安装说明。

v0.1.2 是 Apple Silicon 公开预览版。安装包为 1,837,416 字节，SHA-256 为 `93b6209f1f9c992b0bf9e9853201304e1d4aa45633bc5d31b651a549a7fc4a70`。 [发布页](https://github.com/chendashi1024/ccShot/releases/tag/v0.1.2)
