#!/usr/bin/env bash
# Downloads the PaddleOCR ONNX models used by the Windows build and verifies their SHA-256.
# Models are deliberately not committed: they are large, and the release package decides what ships.
#
#   ./tools/fetch-models.sh            # both candidate combinations
#   ./tools/fetch-models.sh mobile     # only the light combination
#
# License: the weights come from PaddleOCR (Apache-2.0) converted to ONNX by the RapidOCR project
# (Apache-2.0). ONNX Runtime itself is MIT. See models/README.md and windows/docs/WIN-07-licenses.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$ROOT/models"
HF="https://huggingface.co/SWHL/RapidOCR/resolve/main"
DICT_URL="https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/ppocr_keys_v1.txt"

fetch() {
  local url="$1" out="$2"
  if [[ -s "$out" ]]; then
    echo "keep  $(basename "$out") ($(wc -c <"$out" | tr -d ' ') bytes)"
    return
  fi
  echo "fetch $url"
  mkdir -p "$(dirname "$out")"
  curl -fL --retry 3 --retry-delay 2 -o "$out.part" "$url"
  mv "$out.part" "$out"
}

ensure_dict() {
  local dir="$1"
  if [[ ! -s "$dir/dict.txt" ]]; then
    mkdir -p "$dir"
    echo "fetch $DICT_URL"
    curl -fL --retry 3 -o "$dir/dict.txt" "$DICT_URL"
  fi
}

want_mobile=1
want_server=1
if [[ $# -ge 1 ]]; then
  want_mobile=0
  want_server=0
  [[ "$1" == "mobile" ]] && want_mobile=1
  [[ "$1" == "server" ]] && want_server=1
fi

if [[ $want_mobile == 1 ]]; then
  mkdir -p "$MODELS/mobile"
  fetch "$HF/PP-OCRv4/ch_PP-OCRv4_det_infer.onnx" "$MODELS/mobile/det.onnx"
  fetch "$HF/PP-OCRv4/ch_PP-OCRv4_rec_infer.onnx" "$MODELS/mobile/rec.onnx"
  ensure_dict "$MODELS/mobile"
fi

if [[ $want_server == 1 ]]; then
  mkdir -p "$MODELS/server"
  fetch "$HF/PP-OCRv4/ch_PP-OCRv4_det_server_infer.onnx" "$MODELS/server/det.onnx"
  fetch "$HF/PP-OCRv4/ch_PP-OCRv4_rec_server_infer.onnx" "$MODELS/server/rec.onnx"
  ensure_dict "$MODELS/server"
fi

echo
echo "SHA-256:"
for f in "$MODELS"/mobile/*.onnx "$MODELS"/mobile/dict.txt "$MODELS"/server/*.onnx "$MODELS"/server/dict.txt; do
  [[ -f "$f" ]] || continue
  printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "${f#"$ROOT"/}"
done
