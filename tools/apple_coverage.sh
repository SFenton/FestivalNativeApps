#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
swift test --enable-code-coverage

PRODUCTS="$ROOT/apple/.build/out/Products/Debug"
PROFILE="$PRODUCTS/codecov/default.profdata"
xcrun llvm-cov export \
    "$PRODUCTS/FestivalCoreTests.xctest/Contents/MacOS/FestivalCoreTests" \
    --object="$PRODUCTS/FestivalDesignTests.xctest/Contents/MacOS/FestivalDesignTests" \
    --object="$PRODUCTS/FestivalUITests.xctest/Contents/MacOS/FestivalUITests" \
    --instr-profile="$PROFILE" --format=text \
    > "$PRODUCTS/codecov/FestivalApple-merged.json"

python3 "$ROOT/tools/coverage_gate.py" --language swift \
    --report "$PRODUCTS/codecov/FestivalApple-merged.json"
(cd "$ROOT" && python3 -m tools.contrast_gate)
