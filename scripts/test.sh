#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/AgentMonitor.swift" "$ROOT/Tests/MonitorTests.swift" \
  -o "$ROOT/.build/monitor-tests"
"$ROOT/.build/monitor-tests"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/AgentMonitor.swift" "$ROOT/Sources/PetAppearance.swift" \
  "$ROOT/Sources/PetView.swift" "$ROOT/Tests/AppearanceTests.swift" \
  -framework AppKit -o "$ROOT/.build/appearance-tests"
"$ROOT/.build/appearance-tests" "${1:-$ROOT/Resources}"
