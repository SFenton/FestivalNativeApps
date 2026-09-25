#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 || "$1" != "--read-public-live" ]]; then
    printf 'Usage: bash tools/apple_live_service_smoke.sh --read-public-live\n' >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build --package-path "$root/apple" --product FestivalCore --quiet
products="$(swift build --package-path "$root/apple" --show-bin-path)"
tempdir="$(mktemp -d "${TMPDIR:-/tmp}/fst-live-public.XXXXXXXX")"
trap 'rm -f "$tempdir/live-service-smoke"; rmdir "$tempdir"' EXIT
xcrun swiftc -parse-as-library -I "$products" -L "$products" -lFestivalCore \
    "$root/tools/apple_live_service_smoke.swift" -o "$tempdir/live-service-smoke"
"$tempdir/live-service-smoke" --read-public-live
