# 模型目录

模型文件不提交到仓库（体积大、可重新获取）。运行下面的命令下载并校验：

```bash
cd windows
./tools/fetch-models.sh          # mobile + server 两套
./tools/fetch-models.sh mobile   # 只下轻量组合
```

| 目录 | 组合 | 检测 | 识别 | 合计 |
|---|---|---|---|---|
| `models/mobile` | 轻量（试用包默认） | `ch_PP-OCRv4_det_infer.onnx` 4.7 MB | `ch_PP-OCRv4_rec_infer.onnx` 10.4 MB | 14.9 MB |
| `models/server` | 精度优先（只用于对比） | `ch_PP-OCRv4_det_server_infer.onnx` 108 MB | `ch_PP-OCRv4_rec_server_infer.onnx` 86 MB | 194 MB |

字典统一使用 PaddleOCR 的 `ppocr/utils/ppocr_keys_v1.txt`（6623 条）。

运行时期望的目录结构（`tools/package.sh` 会自动复制）：

```
models/mobile/det.onnx
models/mobile/rec.onnx
models/mobile/dict.txt
```

程序查找顺序：设置里的自定义目录 → 程序目录 `models/mobile` → 程序目录 `models` → 向上最多 5 层的 `models/mobile`。
找不到或文件损坏时，只停用“选字”，截图、标注、复制和保存仍可用，并在界面上给出恢复说明。

来源与许可见 [`models.lock.json`](models.lock.json) 和 [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)。
