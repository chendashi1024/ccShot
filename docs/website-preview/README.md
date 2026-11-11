# ccShot 官网

`index.html` 是可离线打开的官网入口。源码片段在 `preview.html`，图片在 `assets/`。五张界面示意来自 [交互设计稿](../ui-v5/ccShot-完整交互预览.html)，图标来自 App 原始资源。

从项目根目录运行 `python3 docs/website-preview/build.py`，生成内嵌图片的离线预览。正式首页在 `website/public/index.html`，通过 [Cloudflare 插件发布](../../website/README.md)。

更新版本时同步下载文件链接、版本号、系统与架构说明。浏览器验收首页、样式切换、图片放大、GitHub、安装说明和真实安装包下载。
