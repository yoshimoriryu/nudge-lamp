#!/usr/bin/env bash
# Installs Nudge Lamp into ~/Applications, starts it, and adds it to your login items.
#
#   curl -fsSL https://raw.githubusercontent.com/yoshimoriryu/nudge-lamp/main/install.sh | bash
#
# Options (after `bash -s --` when piping from curl):
#   --from-source   build with Swift instead of downloading the latest release
#   --no-login      do not add Nudge Lamp to your login items
#   --uninstall     quit Nudge Lamp and remove it
set -euo pipefail

REPO="yoshimoriryu/nudge-lamp"
APP_NAME="Nudge Lamp.app"
DEST="$HOME/Applications"
# NUDGE_LAMP_ZIP_URL lets tests point the installer at a local zip (file:///path/NudgeLamp.zip).
ZIP_URL="${NUDGE_LAMP_ZIP_URL:-https://github.com/$REPO/releases/latest/download/NudgeLamp.zip}"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

mode=release
login=yes
for arg in "$@"; do
  case "$arg" in
    --from-source) mode=source ;;
    --no-login) login=no ;;
    --uninstall) mode=uninstall ;;
    *) die "unknown option: $arg" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "Nudge Lamp runs on macOS only."
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= 15 )) || die "Nudge Lamp needs macOS 15 or later. This Mac runs $macos."

quit_running() {
  if pgrep -x NudgeLamp >/dev/null; then
    say "Quitting the running copy"
    pkill -x NudgeLamp || true
    while pgrep -x NudgeLamp >/dev/null; do sleep 0.2; done
  fi
}

if [[ "$mode" == "uninstall" ]]; then
  quit_running
  if [[ -x "$DEST/$APP_NAME/Contents/MacOS/NudgeLamp" ]]; then
    "$DEST/$APP_NAME/Contents/MacOS/NudgeLamp" --unregister-login-item || true
  fi
  rm -rf "$DEST/$APP_NAME"
  say "Removed $DEST/$APP_NAME"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ "$mode" == "release" ]]; then
  say "Downloading the latest release"
  if curl -fsL "$ZIP_URL" -o "$work/NudgeLamp.zip"; then
    ditto -x -k "$work/NudgeLamp.zip" "$work"
  else
    say "Download failed, building from source instead"
    mode=source
  fi
fi

if [[ "$mode" == "source" ]]; then
  command -v swift >/dev/null || die "Swift not found. Install the command line tools with: xcode-select --install"
  # Use this checkout when the script runs from one, otherwise clone the repo.
  src="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  if ! grep -qs '"NudgeLamp"' "$src/Package.swift"; then
    say "Cloning $REPO"
    git clone --quiet --depth 1 "https://github.com/$REPO.git" "$work/src"
    src="$work/src"
  fi
  say "Building from source, this takes about a minute"
  "$src/scripts/build-app.sh" >/dev/null
  ditto "$src/build/$APP_NAME" "$work/$APP_NAME"
fi

[[ -d "$work/$APP_NAME" ]] || die "no $APP_NAME was produced"

quit_running
mkdir -p "$DEST"
rm -rf "$DEST/$APP_NAME"
ditto "$work/$APP_NAME" "$DEST/$APP_NAME"

if [[ "$login" == "yes" ]]; then
  open "$DEST/$APP_NAME" --args --enable-login-item
else
  open "$DEST/$APP_NAME"
fi

say "Installed $DEST/$APP_NAME and started it."
say "Look for the critter in the menu bar. macOS will ask to allow notifications."
say "Click the critter for setup items if banners or terminal tab switching are not allowed yet."
