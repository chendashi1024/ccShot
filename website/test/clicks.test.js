import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  dataPoint,
  downloadConfig,
  handleRequest,
  resolveClick,
  validHttps,
} from "../src/index.js";

const R2 = "https://download.ccshot.app/ccShot-0.1.0-macos-arm64.dmg";
const GITHUB = "https://github.com/chendashi1024/ccShot/releases/download/v0.1.0/ccShot-0.1.0-macos-arm64.dmg";
const REPO = "https://github.com/chendashi1024/ccShot";
const RELEASE = "https://github.com/chendashi1024/ccShot/releases/tag/v0.1.0";

function fakeEnv() {
  return {
    points: [],
    CLICKS: {
      writeDataPoint(point) {
        fakeEnv.points.push(point);
      },
    },
    ASSETS: {
      fetch() {
        return new Response("asset", { status: 200 });
      },
    },
  };
}
fakeEnv.points = [];

test("primary download redirects to the verified R2 file", () => {
  const decision = resolveClick(new URL("https://ccshot.app/go/download?utm=ignored"));
  assert.equal(decision.event, "download_r2");
  assert.equal(decision.kind, "0.1.0");
  assert.equal(decision.location, R2);
  assert.equal(downloadConfig.r2DownloadUrl, R2);
});

test("github backup stays on the release asset", () => {
  const decision = resolveClick(new URL("https://ccshot.app/go/download?source=github&next=https://evil.example"));
  assert.equal(decision.event, "download_github");
  assert.equal(decision.location, GITHUB);
});

test("missing R2 config falls back to GitHub without claiming an R2 click", () => {
  const decision = resolveClick(new URL("https://ccshot.app/go/download"), {
    ...downloadConfig,
    r2DownloadUrl: null,
  });
  assert.equal(decision.event, "download_github");
  assert.equal(decision.location, GITHUB);
});

test("unsafe configured URLs are not used", () => {
  for (const bad of ["http://download.ccshot.app/a.dmg", "javascript:alert(1)", "https://user:pass@download.ccshot.app/a.dmg"]) {
    assert.equal(validHttps(bad), false);
    const decision = resolveClick(new URL("https://ccshot.app/go/download"), {
      ...downloadConfig,
      r2DownloadUrl: bad,
    });
    assert.equal(decision.event, "download_github");
    assert.equal(decision.location, GITHUB);
  }
});

test("github exits are separate and allowlisted", () => {
  const repo = resolveClick(new URL("https://ccshot.app/go/github?to=repo"));
  const release = resolveClick(new URL("https://ccshot.app/go/github?to=release"));
  const missing = resolveClick(new URL("https://ccshot.app/go/github"));
  const evil = resolveClick(new URL("https://ccshot.app/go/github?to=https://evil.example"));
  assert.deepEqual([repo.event, repo.kind, repo.location], ["github_exit", "repo", REPO]);
  assert.deepEqual([release.event, release.kind, release.location], ["github_exit", "release", RELEASE]);
  assert.equal(missing.location, REPO);
  assert.equal(evil.status, 404);
  assert.equal(resolveClick(new URL("https://ccshot.app/go/download?source=r2")).status, 404);
});

test("datapoints contain only event, kind, and a count", () => {
  const point = dataPoint("download_r2", "0.1.0");
  assert.deepEqual(Object.keys(point).sort(), ["blobs", "doubles", "indexes"]);
  assert.deepEqual(point, { indexes: ["download_r2"], blobs: ["0.1.0"], doubles: [1] });
  assert.throws(() => dataPoint("star", "repo"));
});

test("GET records one point and redirects; HEAD does not record", async () => {
  fakeEnv.points = [];
  const env = fakeEnv();
  const response = await handleRequest(new Request("https://ccshot.app/go/download"), env);
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), R2);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(fakeEnv.points.length, 1);
  assert.equal(fakeEnv.points[0].indexes[0], "download_r2");

  const head = await handleRequest(new Request("https://ccshot.app/go/github?to=repo", { method: "HEAD" }), env);
  assert.equal(head.status, 302);
  assert.equal(head.headers.get("location"), REPO);
  assert.equal(fakeEnv.points.length, 1);
});

test("counting failure still redirects", async () => {
  const env = {
    CLICKS: {
      writeDataPoint() {
        throw new Error("dataset unavailable");
      },
    },
  };
  const response = await handleRequest(new Request("https://ccshot.app/go/download?source=github"), env);
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), GITHUB);
});

test("static requests are not handled as clicks", async () => {
  fakeEnv.points = [];
  const env = fakeEnv();
  const response = await handleRequest(new Request("https://ccshot.app/"), env);
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "asset");
  assert.equal(fakeEnv.points.length, 0);
  const missing = await handleRequest(new Request("https://ccshot.app/go/other"), env);
  assert.equal(missing.status, 404);
});

test("worker source does not collect identity or inject analytics", () => {
  const source = readFileSync(new URL("../src/index.js", import.meta.url), "utf8");
  for (const forbidden of ["cf-connecting-ip", "user-agent", "request.cf", "beacon.min.js", "6bffcc240dec48229fcfddc6087a2842"]) {
    assert.equal(source.includes(forbidden), false, forbidden);
  }
});
