#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
swiftc -O -swift-version 5 "$ROOT"/Sources/Shared/*.swift "$ROOT/Tools/Snapshot/main.swift" -o "$ROOT/build/snapshot"
MDVIEWER_KATEX="$ROOT/Vendor/katex/katex.min.js" MDVIEWER_MERMAID="$ROOT/Vendor/mermaid/mermaid.min.js" "$ROOT/build/snapshot" "$@"
