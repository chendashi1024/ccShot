# ccShot 官网

`index.html` 是可离线打开的官网入口。页面和样式在 `preview.html`，两版共用的元数据在 `head.html`，图片在 `assets/`。五张界面示意来自 [交互设计稿](../ui-v5/ccShot-完整交互预览.html)，图标来自 App 原始资源。

从项目根目录运行 `python3 docs/website-preview/build.py`，同时生成离线预览和正式首页 `website/public/index.html`。两版内容、样式和 JSON-LD 一致；正式页使用 `/go/*` 跳转，离线页直接链接 R2 和 GitHub。FAQ 结构化答案取自源片段的可见问答。不要直接修改生成的 HTML。

示意截图仍内嵌，站点图标独立存放在 `website/public/`；离线页通过相对路径引用图标，需保留仓库目录结构。`--inline-output` 仍可生成会话预览片段。构建仅写本地文件，不发布。正式发布另见[官网发布说明](../../website/README.md)。

更新版本时同步下载文件链接、版本号、系统与架构说明。浏览器验收首页、样式切换、图片放大、GitHub、安装说明和真实安装包下载。
