#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
output="${1:-results/run-$(date +%Y%m%dT%H%M%S)}"
mkdir -p "$output/fixtures"
bash build.sh
python3 -m unittest discover -s Tests -v
build/ccShotPrototype.app/Contents/MacOS/ccShotPrototype --benchmark "$output/fixtures" "$output/raw.json"
python3 metrics.py "$output/fixtures/manifest.json" "$output/raw.json" "$output/summary.json"
