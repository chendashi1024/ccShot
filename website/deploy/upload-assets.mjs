import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";

async function readJson(name) {
  return JSON.parse(await readFile(new URL(name, import.meta.url), "utf8"));
}

async function upload(accountId, { jwt, buckets }) {
  if (typeof jwt !== "string" || !jwt || !Array.isArray(buckets)) {
    throw new Error("缺少 Cloudflare 上传会话");
  }
  if (buckets.length === 0) return jwt;

  const { manifest } = await readJson("manifest.json");
  const types = await readJson("content-types.json");
  const assets = new Map(Object.entries(manifest).map(([path, asset]) => [asset.hash, { path, size: asset.size }]));
  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${accountId}/workers/assets/upload?base64=true`;

  let completionJwt;
  for (const bucket of buckets) {
    const form = new FormData();
    for (const hash of bucket) {
      const asset = assets.get(hash);
      if (!asset) throw new Error("Cloudflare 返回了清单之外的文件哈希");
      const bytes = await readFile(new URL(`../public${asset.path}`, import.meta.url));
      if (bytes.length !== asset.size) throw new Error(`静态文件大小与清单不符：${asset.path}`);
      form.append(hash, new Blob([bytes.toString("base64")], { type: types[asset.path] }), hash);
    }

    const response = await fetch(endpoint, {
      method: "POST",
      headers: { authorization: `Bearer ${jwt}` },
      body: form,
      redirect: "error",
      signal: AbortSignal.timeout(60_000),
    });
    if (!response.ok) throw new Error(`Cloudflare 上传静态文件失败（HTTP ${response.status}）`);
    if (response.status === 201) {
      const result = await response.json();
      completionJwt = result.result?.jwt;
    }
  }

  if (!completionJwt) throw new Error("Cloudflare 未返回静态文件上传完成凭据");
  return completionJwt;
}

const accountId = process.argv[2];
if (!/^[0-9a-f]{32}$/.test(accountId ?? "")) {
  console.error("请传入 Cloudflare 账号 ID");
  process.exit(1);
}

// 凭据仅在进程间通过标准输入和标准输出传递。
const input = createInterface({ input: process.stdin });
try {
  const { value: line } = await input[Symbol.asyncIterator]().next();
  let session;
  try {
    session = JSON.parse(line);
  } catch {
    throw new Error("上传会话必须是单行 JSON");
  }
  const jwt = await upload(accountId, session);
  process.stdout.write(JSON.stringify({ jwt }) + "\n");
} catch (error) {
  console.error(error instanceof SyntaxError ? "Cloudflare 返回了无效的 JSON" : error.message);
  process.exitCode = 1;
} finally {
  input.close();
}
