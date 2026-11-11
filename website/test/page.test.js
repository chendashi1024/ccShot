import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

const site = readFileSync(new URL("../public/index.html", import.meta.url), "utf8");
const offline = readFileSync(new URL("../../docs/website-preview/index.html", import.meta.url), "utf8");
const metadata = JSON.parse(readFileSync(new URL("../deploy/metadata.json", import.meta.url), "utf8"));

function hrefs(html, marker) {
  return [...html.matchAll(new RegExp(`<a\\b[^>]*${marker}[^>]*>`, "g"))].map((match) => {
    const href = match[0].match(/href="([^"]*)"/);
    return href ? href[1] : "";
  });
}

test("deployed page uses download and GitHub redirects", () => {
  assert.deepEqual(hrefs(site, 'data-exit="download"'), ["/go/download", "/go/download"]);
  assert.deepEqual(hrefs(site, 'data-exit="download-github"'), ["/go/download?source=github"]);
  assert.ok(hrefs(site, 'data-exit="github"').every((href) => href === "/go/github?to=repo"));
  assert.deepEqual(hrefs(site, 'data-exit="release"'), ["/go/github?to=release"]);
  assert.ok(site.includes("GitHub 标星"));
  assert.ok(site.includes("https://download.ccshot.app/ccShot-0.1.0-macos-arm64.dmg"));
  assert.ok(site.includes("https://download.ccshot.app/ccShot-0.1.0-macos-arm64.dmg.sha256"));
  assert.equal((site.match(/<h1>/g) || []).length, 1);
  assert.ok(site.includes('lang="zh-CN"'));
  assert.ok(site.includes('name="viewport"'));
  assert.ok(site.includes('rel="canonical" href="https://ccshot.app/"'));
  assert.ok(site.includes("v0.1.0 公开预览版 · Apple Silicon（arm64）"));
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
  const release = "https://github.com/chendashi1024/ccShot/releases";
  const asset = `${release}/download/v0.1.2/ccShot-0.1.2-macos-arm64.dmg`;
  assert.equal(links.filter((link) => link === asset).length, 2);
  assert.ok(links.includes(`${release}/tag/v0.1.2`));
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
