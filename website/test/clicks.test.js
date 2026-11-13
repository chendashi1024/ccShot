import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  dataPoint,
  handleRequest,
  resolveClick,
} from "../src/index.js";

const R2 = "https://download.ccshot.app";
const REPO = "https://github.com/chendashi1024/ccShot";
const VERSION = readFileSync(new URL("../../VERSION", import.meta.url), "utf8").trim();
const MAC = `${R2}/ccShot-${VERSION}-macos-arm64.dmg`;
const WINDOWS = `${R2}/ccShot-${VERSION}-windows-x64.zip`;
const RELEASE = `${REPO}/releases/tag/v${VERSION}`;

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

test("Mac 和 Windows 下载指向 Cloudflare 文件", () => {
  for (const [query, expected] of [["utm=ignored", MAC], ["platform=macos", MAC], ["platform=windows", WINDOWS]]) {
    const decision = resolveClick(new URL(`https://ccshot.app/go/download?${query}`));
    assert.deepEqual(decision, { status: 302, event: "download_r2", kind: VERSION, location: expected });
  }
  assert.equal(resolveClick(new URL("https://ccshot.app/go/download?platform=other")).status, 404);
});

test("旧下载链接也会转到 Cloudflare", () => {
  for (const [platform, expected] of [["macos", MAC], ["windows", WINDOWS]]) {
    const decision = resolveClick(new URL(`https://ccshot.app/go/download?platform=${platform}&source=github&next=https://evil.example`));
    assert.equal(decision.location, expected);
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
  assert.equal(response.headers.get("location"), MAC);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(fakeEnv.points.length, 1);
  assert.deepEqual(fakeEnv.points[0], { indexes: ["download_r2"], blobs: [VERSION], doubles: [1] });

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
  assert.equal(response.headers.get("location"), MAC);
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
