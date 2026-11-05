#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swiftc -O -swift-version 5 Sources/Shared/*.swift Tests/main.swift -o build/renderer-tests
MDVIEWER_KATEX=Vendor/katex/katex.min.js MDVIEWER_MERMAID=Vendor/mermaid/mermaid.min.js build/renderer-tests Tests/Fixtures
