"""Write the Workers static-asset manifest.

Hash matches Wrangler: blake3(base64(file bytes) + extension).hex()[:32].
The extension is the characters after the final dot, without the dot.
"""
from pathlib import Path
import base64
import json
import blake3

public = Path(__file__).resolve().parents[1] / "public"
out = Path(__file__).resolve().parent
content_types = {
    ".html": "text/html; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
    ".xml": "application/xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}
manifest = {}
types = {}
for path in sorted(p for p in public.rglob("*") if p.is_file()):
    rel = "/" + path.relative_to(public).as_posix()
    raw = path.read_bytes()
    extension = path.suffix[1:]
    digest = blake3.blake3(base64.b64encode(raw) + extension.encode()).hexdigest()[:32]
    manifest[rel] = {"hash": digest, "size": len(raw)}
    types[rel] = content_types.get(path.suffix.lower(), "application/octet-stream")

(out / "manifest.json").write_text(json.dumps({"manifest": manifest}, ensure_ascii=False, indent=2) + "\n")
(out / "content-types.json").write_text(json.dumps(types, ensure_ascii=False, indent=2) + "\n")
print(f"{len(manifest)} files")
