# ccShot 官网部署包

这是 `ccshot.app` 的可部署静态页和跳转 Worker。本次没有把网站发布到线上。访问统计还没开始记，点击数据集也要等第一次真实跳转之后才会出现。

## 页面上的下载

- 主按钮「免费下载」在部署后先到 `/go/download`，再跳到 `https://download.ccshot.app/ccShot-0.1.0-macos-arm64.dmg`。
- 「GitHub 安装包」到 `/go/download?source=github`，再跳到 GitHub Release 里的同一份 DMG。
- 「GitHub 标星」到 `/go/github?to=repo`。发布页链接到 `/go/github?to=release`。标星要在 GitHub 页面上完成，点一下这里只表示有人离开官网前往 GitHub。
- v0.1.0 是公开预览版，只提供 Apple Silicon（arm64）。安装包是临时签名，没有 Apple 公证。页面不写 Intel 可用，也不写国内直连或加速保证。

已核对的文件：2,035,236 字节，SHA-256 `24bf3982b6d282085ad5fe19ab96b42946c9841fa575a9f6737a188004a9fcfb`。校验文件是 `https://download.ccshot.app/ccShot-0.1.0-macos-arm64.dmg.sha256`。

## 统计

访问量只用 Cloudflare 已经开启的 Web Analytics 自动注入（zone RUM 开着，`auto_install=true`，site tag `aa1ca9f8e8144d7dae72647528326036`）。页面里不要再放 beacon 脚本，也不要填 site token `6bffcc240dec48229fcfddc6087a2842`，否则同一次访问会被记两次。Web Analytics 不能记自定义点击。

下载和 GitHub 出口由 Worker 写入 Analytics Engine 数据集 `ccshot_clicks`。绑定名是 `CLICKS`。数据集不用提前建，第一次 `writeDataPoint` 会创建。每条只写：

| 字段 | 内容 |
| --- | --- |
| `index1` | `download_r2`、`download_github` 或 `github_exit` |
| `blob1` | 下载记 `0.1.0`；GitHub 出口记 `repo` 或 `release` |
| `double1` | `1` |

不写 IP、完整浏览器标识、账号或可识别身份。`download_r2` 表示有人点了主下载并被转到已核对的地址，不是文件一定下完。`github_exit` 不是已经标星。

部署并点过之后，可用账号 Analytics 读取权限查询：

```sql
SELECT index1 AS event, blob1 AS kind, SUM(_sample_interval) AS clicks
FROM ccshot_clicks
WHERE timestamp > NOW() - INTERVAL '7' DAY
GROUP BY event, kind
ORDER BY clicks DESC
```

把 SQL 正文 POST 到 `https://api.cloudflare.com/client/v4/accounts/ff616a1cf63158f320063c31353d5a30/analytics_engine/sql`。数据可能要过一会儿才出现。

## 为什么用 Workers Static Assets

仓库里没有现成的 ccShot Pages 项目。访问页面本身不需要跑函数；只有统计点击才需要 Worker。Workers Static Assets 可以一次上传静态文件和这段跳转代码。`run_worker_first` 只包含 `/go/*`，首页、图标和校验文本由平台直接返回。不要把它设成 `true`，否则每次打开首页都会调用函数。

`not_found_handling` 是 `404-page`。这时没被列进 `run_worker_first` 的未知地址会返回 `404.html`。所以 `/go/*` 必须留在这个窄名单里，点击才会被记下。

不要把 `download.ccshot.app` 绑到这个 Worker。那个主机名已经指向安装包。这里只绑定 `ccshot.app`。

## 部署

账号 `ff616a1cf63158f320063c31353d5a30`，zone `ccshot.app`（`759006d6464177df51c03bb343482584`）。Worker 名称 `ccshot-site`。静态文件在 `public/`，清单在 `deploy/manifest.json`，每个文件的上传 Content-Type 在 `deploy/content-types.json`。清单哈希与 Wrangler 相同：对「文件内容的 base64 文本 + 不带点的扩展名」做 blake3，再取十六进制前 32 位。

1. 用 API token POST `deploy/manifest.json` 到  
   `/accounts/ff616a1cf63158f320063c31353d5a30/workers/scripts/ccshot-site/assets-upload-session`。
2. 返回的 `buckets` 里每一组哈希，POST 到  
   `/accounts/ff616a1cf63158f320063c31353d5a30/workers/assets/upload?base64=true`。  
   这一步的 `Authorization` 用上传会话返回的 jwt，不是账号 token。表单字段名是哈希，内容是文件的 base64，字段的 Content-Type 用 `content-types.json` 里的值。全部传完会得到 201 和 completion jwt。若 `buckets` 为空，会话 jwt 本身就是 completion jwt。
3. PUT `/accounts/ff616a1cf63158f320063c31353d5a30/workers/scripts/ccshot-site`，`multipart/form-data`：  
   - `metadata`：`deploy/metadata.json`，把 `assets.jwt` 换成上一步的 completion jwt，Content-Type 为 `application/json`。  
   - `index.js`：`src/index.js`，Content-Type 为 `application/javascript+module`。
4. PUT `/accounts/ff616a1cf63158f320063c31353d5a30/workers/domains`，正文用 `deploy/domain.json`。

上线后用这三条确认跳转，再跑上面的 SQL，看到对应事件才算点击采集生效：

```bash
curl -sI https://ccshot.app/go/download
curl -sI "https://ccshot.app/go/download?source=github"
curl -sI "https://ccshot.app/go/github?to=repo"
```

期望的 `location` 依次是 R2 的 DMG、GitHub 的 DMG、GitHub 仓库。首页源码里不应出现 `beacon.min.js`。

本地检查：

```bash
python3 docs/website-preview/build.py
python3 website/deploy/make-manifest.py
node --test website/test/*.js
```

## 还没做

- 没有执行上面的上传，`ccshot.app` 还没有这个网站。
- 访问数字要等页面通过该域名对外提供之后，才会进入已经开启的 Web Analytics。
- `ccshot_clicks` 要等部署后的第一次跳转才会出现；现在查询不会有这张表。
- 没有发 GitHub Release，没有改 App，没有做推广。
