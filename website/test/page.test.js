import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";
import { downloadConfig } from "../src/index.js";

const site = readFileSync(new URL("../public/index.html", import.meta.url), "utf8");
const offline = readFileSync(new URL("../../docs/website-preview/index.html", import.meta.url), "utf8");
const metadata = JSON.parse(readFileSync(new URL("../deploy/metadata.json", import.meta.url), "utf8"));
const version = readFileSync(new URL("../../VERSION", import.meta.url), "utf8").trim();
const compatibility = "macOS 14+（Apple Silicon）· Windows x64";

function hrefs(html, marker) {
  return [...html.matchAll(new RegExp(`<a\\b[^>]*${marker}[^>]*>`, "g"))].map((match) => {
    const href = match[0].match(/href="([^"]*)"/);
    return href ? href[1] : "";
  });
}

test("deployed page uses download and GitHub redirects", () => {
  assert.deepEqual(hrefs(site, 'data-exit="download"'), [
    "/go/download", "/go/download?platform=windows",
    "/go/download", "/go/download?platform=windows",
  ]);
  assert.ok(hrefs(site, 'data-exit="github"').every((href) => href === "/go/github?to=repo"));
  assert.deepEqual(hrefs(site, 'data-exit="release"'), ["/go/github?to=release"]);
  assert.ok(site.includes("GitHub 标星"));
  const structured = JSON.parse(site.match(/<script type="application\/ld\+json">([^<]+)<\/script>/)[1]);
  assert.equal(structured.softwareVersion, version);
  assert.deepEqual(structured.downloadUrl, [downloadConfig.macDownload, downloadConfig.windowsDownload]);
  assert.equal((site.match(/<h1>/g) || []).length, 1);
  assert.ok(site.includes('lang="zh-CN"'));
  assert.ok(site.includes('name="viewport"'));
  assert.ok(site.includes('rel="canonical" href="https://ccshot.app/"'));
  assert.equal(site.split(compatibility).length - 1, 2);
  assert.equal(site.split(`v${version} · ${compatibility}`).length - 1, 1);
  assert.match(site, /<title>ccShot · 免费截图识字工具，支持 Windows 与 macOS<\/title>/);
  assert.match(site, /<p class="hero-intro">ccShot 是适用于 macOS 和 Windows 的免费截图识字工具/);
});

test("the download section shows one line of compatibility and an installation link", () => {
  const section = site.match(/<section\b[^>]*id="cc-download"[^>]*>([\s\S]*?)<\/section>/)?.[1] ?? "";
  assert.ok(section.includes(`<p class="platform">v${version} · ${compatibility} · <a`));
  assert.equal((section.match(/<p\b/g) ?? []).length, 1);
});

test("public pages open external pages in a new tab", () => {
  const notFound = readFileSync(new URL("../public/404.html", import.meta.url), "utf8");
  for (const page of [site, offline, notFound]) {
    for (const [link, href] of page.matchAll(/<a\b[^>]*\bhref="([^"]+)"[^>]*>/g)) {
      const external = href.startsWith("/go/github") || href.startsWith("https://");
      if (external) {
        assert.match(link, /\btarget="_blank"/, href);
        assert.match(link, /\brel="noopener"/, href);
      } else {
        assert.doesNotMatch(link, /\btarget="_blank"/, href);
      }
    }
  }
});

test("offline page downloads the real files without the worker", () => {
  const links = [...offline.matchAll(/<a\b[^>]*\bhref="([^"]+)"/g)].map((match) => match[1]);
  for (const asset of [downloadConfig.macDownload, downloadConfig.windowsDownload]) {
    assert.equal(links.filter((link) => link === asset).length, 2);
  }
  assert.ok(links.includes(downloadConfig.githubReleasePage));
  assert.ok(links.every((link) => !link.startsWith("/go/")));
});

test("the public page does not double-count visits or overclaim", () => {
  for (const forbidden of [
    "beacon.min.js",
    "static.cloudflareinsights.com",
    "6bffcc240dec48229fcfddc6087a2842",
    "aa1ca9f8e8144d7dae72647528326036",
    "国内",
    "加速",
    "Intel 可用",
    "实测通过",
    "已镜像",
    "一键问 AI",
  ]) {
    for (const page of [site, offline]) assert.equal(page.includes(forbidden), false, forbidden);
  }
});

test("worker metadata keeps static files off the click route", () => {
  assert.equal(metadata.main_module, "index.js");
  assert.deepEqual(metadata.assets.config.run_worker_first, ["/go/*"]);
  assert.equal(metadata.assets.config.not_found_handling, "404-page");
  assert.equal(metadata.observability.enabled, false);
  assert.deepEqual(metadata.bindings, [{ type: "assets", name: "ASSETS" }]);
});

test("asset manifest hashes match Wrangler", () => {
  execFileSync("python3", ["-c", `
import base64, json, pathlib, blake3
root = pathlib.Path(${JSON.stringify(new URL("../", import.meta.url).pathname)})
manifest = json.loads((root / "deploy" / "manifest.json").read_text())["manifest"]
for rel, item in manifest.items():
    path = root / "public" / rel.lstrip("/")
    raw = path.read_bytes()
    digest = blake3.blake3(base64.b64encode(raw) + path.suffix[1:].encode()).hexdigest()[:32]
    assert item["size"] == len(raw), rel
    assert item["hash"] == digest, rel
print(len(manifest))
`], { stdio: "inherit" });
  const source = readFileSync(new URL("../public/index.html", import.meta.url));
  assert.ok(source.byteLength > 1000);
});

test("两版元数据、可见 FAQ 与结构化事实一致", () => {
  for (const page of [site, offline]) {
    const data = [...page.matchAll(/<script type="application\/ld\+json">([^<]+)<\/script>/g)].map(m => JSON.parse(m[1]));
    assert.deepEqual(data.map(item => item['@type']), ['SoftwareApplication', 'WebSite', 'FAQPage']);
    const [app, web, faq] = data;
    assert.deepEqual(app.operatingSystem, ['macOS 14+ (Apple Silicon)', 'Windows x64']);
    assert.equal(app.offers.price, '0');
    assert.equal(app.softwareVersion, version);
    assert.deepEqual(app.downloadUrl, [downloadConfig.macDownload, downloadConfig.windowsDownload]);
    for (const item of [app, web]) assert.deepEqual(item.sameAs, ['https://github.com/chendashi1024/ccShot']);
    assert.doesNotMatch(JSON.stringify(data), /aggregateRating|ratingValue|reviewCount|ratingCount|award/);
    const section = page.match(/<section id="cc-faq"[\s\S]*?<\/section>/)[0];
    const visible = [...section.matchAll(/<dt>(.*?)<\/dt><dd>(.*?)<\/dd>/g)];
    assert.equal(visible.length, 7);
    assert.deepEqual(faq.mainEntity.map(q => [q.name, q.acceptedAnswer.text]), visible.map(m => [m[1], m[2]]));
    assert.doesNotMatch(section, /\bhidden\b|display:\s*none/);
    for (const term of ['截图识字', '截图提取文字', '截图转文字', '免费截图工具', 'VisionKit', 'PP-OCRv4', '无需账号或 API Key']) assert.ok(page.includes(term), term);
    assert.match(page, /name="description" content="ccShot 是免费、MIT 开源的 Windows 与 macOS 截图工具/);
    assert.ok(page.includes('name="robots" content="index,follow"'));
    assert.ok(page.includes('.button:focus-visible{outline:4px solid #2456a0;outline-offset:5px}'));
  }
  assert.equal(site.match(/<section id="cc-faq"[\s\S]*?<\/section>/)[0], offline.match(/<section id="cc-faq"[\s\S]*?<\/section>/)[0]);
});

test("图标尺寸、格式、声明及静态清单完整", () => {
  const manifest = JSON.parse(readFileSync(new URL('../deploy/manifest.json', import.meta.url))).manifest;
  const types = JSON.parse(readFileSync(new URL('../deploy/content-types.json', import.meta.url)));
  for (const [name, size] of [['icon.png', 96], ['apple-touch-icon.png', 180], ['icon-192.png', 192]]) {
    const png = readFileSync(new URL('../public/' + name, import.meta.url));
    assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
    assert.equal(types['/' + name], 'image/png');
    assert.ok(manifest['/' + name]);
    for (const page of [site, offline]) assert.match(page, new RegExp(`<link[^>]+href="[^"]*/${name}"[^>]*sizes="${size}x${size}"`));
  }
  const ico = readFileSync(new URL('../public/favicon.ico', import.meta.url));
  assert.equal(ico.readUInt16LE(0), 0);
  assert.equal(ico.readUInt16LE(2), 1);
  const sizes = [];
  for (let i = 0; i < ico.readUInt16LE(4); i++) {
    const offset = 6 + i * 16;
    const width = ico[offset] || 256;
    assert.equal(width, ico[offset + 1] || 256);
    assert.ok(ico.readUInt32LE(offset + 12) + ico.readUInt32LE(offset + 8) <= ico.length);
    sizes.push(width);
  }
  assert.deepEqual(sizes, [16, 32, 48, 64, 128, 256]);
  assert.equal(types['/favicon.ico'], 'image/vnd.microsoft.icon');
  assert.ok(manifest['/favicon.ico']);
  for (const page of [site, offline]) {
    assert.match(page, /<link rel="icon" href="[^"]*\/favicon.ico" type="image\/vnd.microsoft.icon"/);
    assert.doesNotMatch(page, /<link rel="(?:icon|apple-touch-icon)"[^>]*data:/);
  }
  execFileSync('python3', ['-c', `
import json, pathlib
root = pathlib.Path(${JSON.stringify(new URL('../', import.meta.url).pathname)})
manifest = json.loads((root / 'deploy/manifest.json').read_text())['manifest']
assert set(manifest) == {'/' + p.relative_to(root / 'public').as_posix() for p in (root / 'public').rglob('*') if p.is_file()}
`]);
});

test("爬取入口与公开产品资料保持真实", () => {
  const read = name => readFileSync(new URL('../public/' + name, import.meta.url), 'utf8');
  assert.match(read('robots.txt'), /User-agent: \*\nAllow: \//);
  assert.ok(read('robots.txt').includes('Sitemap: https://ccshot.app/sitemap.xml'));
  assert.ok(read('sitemap.xml').includes('<loc>https://ccshot.app/</loc>'));
  const llms = read('llms.txt');
  assert.ok(llms.includes(`v${version}`));
  for (const url of [downloadConfig.macDownload, downloadConfig.windowsDownload]) assert.ok(llms.includes(url));
  for (const term of ['VisionKit', 'PP-OCRv4', '未签名', '尚未随当前版本发行', '无需账号或 API Key']) assert.ok(llms.includes(term), term);
  assert.match(site, /rel="alternate" type="text\/plain" href="\/llms.txt"/);
  const types = JSON.parse(readFileSync(new URL('../deploy/content-types.json', import.meta.url)));
  assert.equal(types['/llms.txt'], 'text/plain; charset=utf-8');
});

test("共同源可重复生成两版首页", () => {
  execFileSync('python3', ['docs/website-preview/build.py'], { cwd: new URL('../../', import.meta.url), stdio: 'inherit' });
  assert.equal(readFileSync(new URL('../public/index.html', import.meta.url), 'utf8'), site);
  assert.equal(readFileSync(new URL('../../docs/website-preview/index.html', import.meta.url), 'utf8'), offline);
});
