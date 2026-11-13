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
  assert.match(site, /<title>ccShot · macOS 和 Windows 截图工具<\/title>/);
  assert.match(site, /<p class="hero-intro">适用于 macOS 和 Windows 的截图工具/);
});

test("the download section shows one line of compatibility and an installation link", () => {
  const section = site.match(/<section\b[^>]*id="cc-download"[^>]*>([\s\S]*?)<\/section>/)?.[1] ?? "";
  assert.ok(section.includes(`<p class="platform">v${version} · ${compatibility} · <a`));
  assert.equal((section.match(/<p\b/g) ?? []).length, 1);
});

test("public pages open external pages in a new tab", () => {
  const notFound = readFileSync(new URL("../public/404.html", import.meta.url), "utf8");
  for (const page of [site, notFound]) {
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
    assert.equal(site.includes(forbidden), false, forbidden);
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
