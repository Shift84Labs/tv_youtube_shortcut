#!/usr/bin/env bash
# One-time toolchain setup for building shortcut APKs on Linux / WSL / macOS.
# Installs adb + Android build-tools + a platform android.jar into ~/ (no root
# except for the JDK). Gradle and Android Studio are not needed.
#
# Env: SDK_DIR (default ~/android_sdk), TOOLS_DIR (default ~/platform_tools)
set -euo pipefail

SDK_DIR="${SDK_DIR:-$HOME/android_sdk}"
TOOLS_DIR="${TOOLS_DIR:-$HOME/platform_tools}"
case "$(uname -s)" in
  Darwin) OS=macosx ;;
  *)      OS=linux  ;;
esac
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v javac >/dev/null || {
  echo "!! No JDK found. Install one first, e.g.:"
  echo "     sudo apt-get install -y openjdk-17-jdk-headless   # Debian/Ubuntu"
  echo "     brew install openjdk@17                           # macOS"
  exit 1
}

if [ ! -x "$TOOLS_DIR/adb" ]; then
  echo "==> platform-tools (adb)"
  curl -fsSL -o "$TMP/pt.zip" "https://dl.google.com/android/repository/platform-tools-latest-$OS.zip"
  unzip -oq "$TMP/pt.zip" -d "$TMP/pt"
  mkdir -p "$TOOLS_DIR"
  cp -r "$TMP/pt/platform-tools/." "$TOOLS_DIR/"
fi

# Resolve real archive names from Google's manifest. Hardcoded cmdline-tools URLs
# 404 as soon as their build number goes stale, and sdkmanager is not needed here.
echo "==> resolving package names"
curl -fsSL -o "$TMP/repo.xml" https://dl.google.com/android/repository/repository2-3.xml
BT_ZIP="$(grep -oE "build-tools_r[0-9]+(\.[0-9]+)*-$OS\.zip" "$TMP/repo.xml" | sort -V | tail -1)"
PLAT_ZIP="$(grep -oE 'platform-34[a-z0-9._-]*\.zip' "$TMP/repo.xml" | sort -V | tail -1)"
[ -n "$BT_ZIP" ] && [ -n "$PLAT_ZIP" ] || { echo "could not resolve package names" >&2; exit 1; }
echo "    build-tools: $BT_ZIP"
echo "    platform   : $PLAT_ZIP"

if ! find "$SDK_DIR/build-tools" -mindepth 1 -maxdepth 1 -type d >/dev/null 2>&1; then
  echo "==> build-tools"
  curl -fsSL -o "$TMP/bt.zip" "https://dl.google.com/android/repository/$BT_ZIP"
  mkdir -p "$SDK_DIR/build-tools"
  unzip -oq "$TMP/bt.zip" -d "$SDK_DIR/build-tools"
fi

if ! find "$SDK_DIR/platforms" -name android.jar >/dev/null 2>&1; then
  echo "==> platform"
  curl -fsSL -o "$TMP/plat.zip" "https://dl.google.com/android/repository/$PLAT_ZIP"
  mkdir -p "$SDK_DIR/platforms"
  unzip -oq "$TMP/plat.zip" -d "$SDK_DIR/platforms"
fi

echo
echo "adb        : $TOOLS_DIR/adb"
echo "build-tools: $(find "$SDK_DIR/build-tools" -mindepth 1 -maxdepth 1 -type d | tail -1)"
echo "android.jar: $(find "$SDK_DIR/platforms" -name android.jar | tail -1)"
echo "ready. next: ./build_shortcut.sh <video_id> \"<Label>\""
