# ccShot 官网

`index.html` 是可离线打开的官网入口。源码片段在 `preview.html`，图片在 `assets/`。五张界面示意来自 [交互设计稿](../ui-v5/ccShot-完整交互预览.html)，图标来自 App 原始资源。

从项目根目录运行 `python3 docs/website-preview/build.py`，生成内嵌图片的独立页面，并写出 `website/public/`。离线打开 `index.html` 时，主下载直接指向已核对的 GitHub 安装包。正式站点由 `website/` 里的 Worker 先记下点击再跳转，部署步骤见 [website/README.md](../../website/README.md)。

更新版本时同步下载文件链接、版本号、系统与架构说明。浏览器验收首页、样式切换、图片放大、GitHub 标星、安装说明和真实安装包下载。官网称 v0.1.2 为公开预览版，只写 Apple Silicon（arm64），不写国内加速保证。
