// Click redirects for ccshot.app.
// Counts are redirect requests, not completed downloads and not GitHub stars.

const version = "0.1.3";
const repository = "https://github.com/chendashi1024/ccShot";
const downloads = "https://download.ccshot.app";

export const downloadConfig = {
  version,
  macDownload: `${downloads}/ccShot-${version}-macos-arm64.dmg`,
  windowsDownload: `${downloads}/ccShot-${version}-windows-x64.zip`,
  githubReleasePage: `${repository}/releases/tag/v${version}`,
  githubRepository: repository,
};

const EVENTS = new Set(["download_r2", "github_exit"]);

export function dataPoint(event, kind) {
  if (!EVENTS.has(event)) throw new Error("unknown event");
  if (typeof kind !== "string" || kind.length === 0 || kind.length > 32) throw new Error("unknown kind");
  return { indexes: [event], blobs: [kind], doubles: [1] };
}

function normalizePath(pathname) {
  if (pathname.length > 1 && pathname.endsWith("/")) return pathname.slice(0, -1);
  return pathname;
}

export function resolveClick(url, config = downloadConfig) {
  const path = normalizePath(url.pathname);
  if (path === "/go/download") {
    const source = url.searchParams.get("source");
    const platform = url.searchParams.get("platform") ?? "macos";
    if (source !== null && source !== "github") return { status: 404 };
    if (platform !== "macos" && platform !== "windows") return { status: 404 };
    return {
      status: 302,
      event: "download_r2",
      kind: config.version,
      location: platform === "windows" ? config.windowsDownload : config.macDownload,
    };
  }
  if (path === "/go/github") {
    const to = url.searchParams.get("to");
    if (to === null || to === "repo") {
      return { status: 302, event: "github_exit", kind: "repo", location: config.githubRepository };
    }
    if (to === "release") {
      return { status: 302, event: "github_exit", kind: "release", location: config.githubReleasePage };
    }
    return { status: 404 };
  }
  return null;
}

function text(body, status, extra) {
  const headers = new Headers({
    "content-type": "text/plain; charset=utf-8",
    "cache-control": "no-store",
  });
  if (extra) {
    for (const [key, value] of Object.entries(extra)) headers.set(key, value);
  }
  return new Response(body, { status, headers });
}

export async function handleRequest(request, env) {
  const url = new URL(request.url);
  const decision = resolveClick(url);
  if (decision) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return text("方法不被允许", 405, { allow: "GET, HEAD" });
    }
    if (decision.status === 404) return text("未找到", 404);
    if (request.method === "GET" && env.CLICKS && typeof env.CLICKS.writeDataPoint === "function") {
      try {
        env.CLICKS.writeDataPoint(dataPoint(decision.event, decision.kind));
      } catch {
        // The file redirect still happens when counting fails.
      }
    }
    return new Response(null, {
      status: 302,
      headers: {
        location: decision.location,
        "cache-control": "no-store",
        "referrer-policy": "strict-origin-when-cross-origin",
      },
    });
  }
  if (normalizePath(url.pathname).startsWith("/go/")) return text("未找到", 404);
  if (env.ASSETS && typeof env.ASSETS.fetch === "function") return env.ASSETS.fetch(request);
  return text("未找到", 404);
}

export default {
  fetch(request, env) {
    return handleRequest(request, env);
  },
};
