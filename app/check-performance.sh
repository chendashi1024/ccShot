#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh
xcrun swiftc -parse-as-library Tests/DisplayFixtureHost.swift -o build/display-fixture-host
python3 Tests/run_performance.py --output "$PWD/build/performance/$(date +%Y%m%d-%H%M%S)"
