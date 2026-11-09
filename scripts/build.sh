#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${AGENT_PET_OUTPUT_APP:-$ROOT/dist/AgentPet.app}"
VERSION="${AGENT_PET_VERSION:-0.1.1}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
read -r -a architectures <<< "${ARCHS:-$(uname -m)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid AGENT_PET_VERSION' >&2; exit 1; }
mkdir -p "$ROOT/.build/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
binaries=()
for architecture in "${architectures[@]}"; do
  case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;; esac
  binary="$ROOT/.build/AgentPet-$architecture"
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" \
    -target "$architecture-apple-macos13.0" \
    -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT"/Sources/*.swift -framework AppKit -o "$binary"
  binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/AgentPet"
for state in idle calm steady busy heated rush; do
  cp "$ROOT/Resources/$state-atlas.png" "$ROOT/Resources/$state.json" "$APP/Contents/Resources/"
done
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jinwoo.agentpet</string>
<key>CFBundleName</key><string>AgentPet</string>
<key>CFBundleDisplayName</key><string>AgentPet</string>
<key>CFBundleExecutable</key><string>AgentPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
