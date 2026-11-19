#!/usr/bin/env bash
# Builds build/Agent Lamp.app from the SwiftPM release binary.
# UNIVERSAL=1 builds for both Apple silicon and Intel. That needs a full Xcode install.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Agent Lamp.app"

args=(-c release --product AgentLamp)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  args+=(--arch arm64 --arch x86_64)
fi

swift build "${args[@]}"
BIN="$(swift build "${args[@]}" --show-bin-path)/AgentLamp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AgentLamp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. Banners and the Automation prompt need a signed bundle.
# The linker already signs arm64 binaries, so silence the "replacing existing signature" note.
codesign --force --sign - "$APP" 2>/dev/null

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/AgentLamp"))"
