#!/usr/bin/env bash
# Builds build/Agent Lamp.app from the SwiftPM release binary.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Agent Lamp.app"

swift build -c release --product AgentLamp
BIN="$(swift build -c release --show-bin-path)/AgentLamp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AgentLamp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. Banners and the Automation prompt need a signed bundle.
codesign --force --sign - "$APP"

echo "Built $APP"
