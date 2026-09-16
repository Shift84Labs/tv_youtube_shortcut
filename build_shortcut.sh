#!/usr/bin/env bash
# Build (and optionally install) an Android TV home-screen tile that opens one
# YouTube video directly.
#
# Usage:  ./build_shortcut.sh <video_id> <label> [adb_target]
#
# Env:
#   YT_TARGET   <package>/<activity> of the YouTube app to hand the video to.
#               Default is the Google TV / Android TV client.
#               Fire TV ships a different client, see docs/SIDELOADING.md.
#               Set to "auto" to detect it from a connected device (needs adb_target).
#   SDK_DIR     Android SDK dir, default ~/android_sdk  (see setup_toolchain.sh)
#   ADB         adb binary,      default ~/platform_tools/adb
#
# Examples:
#   ./build_shortcut.sh dQw4w9WgXcQ "Never Gonna"
#   ./build_shortcut.sh dQw4w9WgXcQ "Never Gonna" 192.168.1.50:5555
#   YT_TARGET=auto ./build_shortcut.sh dQw4w9WgXcQ "Never Gonna" 192.168.1.50:5555
set -euo pipefail

VIDEO_ID="${1:?usage: build_shortcut.sh <video_id> <label> [adb_target]}"
LABEL="${2:?usage: build_shortcut.sh <video_id> <label> [adb_target]}"
ADB_TARGET="${3:-}"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$PROJ/template"
SDK_DIR="${SDK_DIR:-$HOME/android_sdk}"
ADB="${ADB:-$HOME/platform_tools/adb}"
KS="$PROJ/shortcut_keystore.jks"
OUT="$PROJ/out"

YT_TARGET="${YT_TARGET:-com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity}"

# Build-tools unpacks to a dir named for its release, which is not the API level.
BT="$(find "$SDK_DIR/build-tools" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"
ANDROID_JAR="$(find "$SDK_DIR/platforms" -maxdepth 2 -name android.jar 2>/dev/null | sort | tail -1)"
[ -x "$BT/aapt2" ]      || { echo "no build-tools under $SDK_DIR, run ./setup_toolchain.sh" >&2; exit 1; }
[ -f "$ANDROID_JAR" ]   || { echo "no android.jar under $SDK_DIR, run ./setup_toolchain.sh" >&2; exit 1; }

adb_dev() { "$ADB" -s "$ADB_TARGET" "$@"; }

if [ "$YT_TARGET" = "auto" ]; then
  [ -n "$ADB_TARGET" ] || { echo "YT_TARGET=auto needs an adb_target" >&2; exit 1; }
  for cand in com.google.android.youtube.tv com.amazon.firetv.youtube com.google.android.youtube.tvkids; do
    if adb_dev shell pm list packages 2>/dev/null | grep -q "^package:$cand$"; then
      act="$(adb_dev shell cmd package resolve-activity --brief \
              -c android.intent.category.LEANBACK_LAUNCHER "$cand" 2>/dev/null | tail -1 | tr -d '\r')"
      YT_TARGET="${act:-$cand/}"
      break
    fi
  done
  [ "$YT_TARGET" = "auto" ] && { echo "could not detect a YouTube app on $ADB_TARGET" >&2; exit 1; }
  echo "detected target: $YT_TARGET"
fi

YT_PKG="${YT_TARGET%%/*}"
YT_ACT="${YT_TARGET#*/}"
[ -n "$YT_PKG" ] && [ -n "$YT_ACT" ] && [ "$YT_PKG" != "$YT_ACT" ] \
  || { echo "YT_TARGET must be <package>/<activity>, got: $YT_TARGET" >&2; exit 1; }

# Video ids contain - and _, which are illegal in a java package segment.
PKG="dev.shift84labs.ytshortcut.v$(echo "$VIDEO_ID" | tr -c '[:alnum:]' '_')"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/res/drawable" "$W/src/shortcut" "$W/classes" "$W/dex" "$OUT"

# mqdefault.jpg is served at exactly 320x180, the Android TV banner size.
curl -fsSL -o "$W/res/drawable/banner.jpg" \
  "https://i.ytimg.com/vi/$VIDEO_ID/mqdefault.jpg"

sed -e "s|__VIDEO_ID__|$VIDEO_ID|g" -e "s|__YT_PKG__|$YT_PKG|g" -e "s|__YT_ACT__|$YT_ACT|g" \
  "$TPL/src/shortcut/MainActivity.java" > "$W/src/shortcut/MainActivity.java"
sed -e "s|__PKG__|$PKG|g" -e "s|__LABEL__|$LABEL|g" -e "s|__YT_PKG__|$YT_PKG|g" \
  "$TPL/AndroidManifest.xml" > "$W/AndroidManifest.xml"

"$BT/aapt2" compile --dir "$W/res" -o "$W/res.zip"
"$BT/aapt2" link -o "$W/unsigned.apk" -I "$ANDROID_JAR" \
  --manifest "$W/AndroidManifest.xml" -R "$W/res.zip" \
  --min-sdk-version 21 --target-sdk-version 34

javac -nowarn -source 8 -target 8 -bootclasspath "$ANDROID_JAR" \
  -d "$W/classes" "$W/src/shortcut/MainActivity.java" 2>/dev/null

"$BT/d8" --lib "$ANDROID_JAR" --min-api 21 --output "$W/dex" "$W/classes/shortcut/"*.class

# aapt add stores the path as given, so add from inside the dex dir.
( cd "$W/dex" && "$BT/aapt" add "$W/unsigned.apk" classes.dex >/dev/null )

# Throwaway self-signed key. Android requires a signature; nothing here depends on
# who signed it. Keep the keystore so rebuilds can upgrade a tile in place.
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -storepass shortcut -keyalg RSA -keysize 2048 \
    -validity 10950 -alias shortcut -dname "CN=tv_youtube_shortcut" 2>/dev/null
fi

"$BT/zipalign" -f 4 "$W/unsigned.apk" "$W/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:shortcut --ks-key-alias shortcut \
  --out "$OUT/$VIDEO_ID.apk" "$W/aligned.apk"

echo "built: $OUT/$VIDEO_ID.apk ($(stat -c%s "$OUT/$VIDEO_ID.apk") bytes)"
echo "  app package : $PKG"
echo "  opens       : $YT_PKG"

if [ -n "$ADB_TARGET" ]; then
  adb_dev install -r "$OUT/$VIDEO_ID.apk"
  echo "installed to $ADB_TARGET"
fi
