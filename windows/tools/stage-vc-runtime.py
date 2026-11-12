"""从锁定的微软 Redist 组件提取 ccShot 用到的 x64 运行库。"""

import hashlib
import io
import json
import sys
import tempfile
import urllib.request
from pathlib import Path
from zipfile import BadZipFile, ZipFile


def read_payload(lock, cache):
    def verified(data):
        return len(data) == lock["bytes"] and hashlib.sha256(data).hexdigest() == lock["sha256"]

    if cache.is_file():
        data = cache.read_bytes()
        if verified(data):
            return data

    with urllib.request.urlopen(lock["url"], timeout=60) as response:
        data = response.read(lock["bytes"] + 1)
    if not verified(data):
        raise ValueError("下载的微软组件与锁定的大小或 SHA-256 不一致")

    cache.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache.parent) as temporary:
        staged = Path(temporary) / cache.name
        staged.write_bytes(data)
        staged.replace(cache)
    return data


def main():
    if len(sys.argv) < 2:
        raise SystemExit("用法：stage-vc-runtime.py <发布目录> [其他发布目录 ...]")

    tools = Path(__file__).resolve().parent
    lock = json.loads((tools / "vc-runtime.lock.json").read_text(encoding="utf-8"))
    cache = tools.parent / "dist" / "vc-runtime" / f'{lock["sha256"]}.vsix'
    with ZipFile(io.BytesIO(read_payload(lock, cache))) as archive:
        files = {name: archive.read(f'{lock["directory"]}/{name}') for name in lock["files"]}

    for name, data in files.items():
        pe_offset = int.from_bytes(data[60:64], "little")
        if data[:2] != b"MZ" or data[pe_offset : pe_offset + 6] != b"PE\0\0\x64\x86":
            raise ValueError(f"{name} 不是 Windows x64 DLL")

    for argument in sys.argv[1:]:
        target = Path(argument)
        if not (target / "onnxruntime.dll").is_file():
            raise ValueError(f"{target} 缺少发布产物 onnxruntime.dll")
        for name, data in files.items():
            path = target / name
            if path.exists() and path.read_bytes() != data:
                raise ValueError(f"{path} 与锁定的运行库冲突")
            path.write_bytes(data)
    print(f'Visual C++ {lock["version"]} x64：已随包放入 {len(files)} 个 DLL。')


if __name__ == "__main__":
    try:
        main()
    except (BadZipFile, KeyError, OSError, ValueError) as error:
        raise SystemExit(f"准备 Visual C++ 运行库失败：{error}") from error
