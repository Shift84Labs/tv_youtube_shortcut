#!/usr/bin/env bash
# Build (and optionally install) an Android TV home-screen tile that opens a
# YouTube video, playlist, or channel directly.
#
# Usage:  ./build_shortcut.sh <target> <label> [adb_target]
#         ./build_shortcut.sh --print-url <target>
#
# <target> may be any of:
#   dQw4w9WgXcQ                                 video id
#   PLxxxxxxxx / UUxxxxxxxx                     playlist id
#   UCxxxxxxxx                                  channel id (uses its uploads playlist)
#   https://www.youtube.com/watch?v=...         any youtube URL, including
#   https://www.youtube.com/live/...            live, shorts, embed, youtu.be
#   https://www.youtube.com/playlist?list=...   and watch URLs carrying a list=
#   https://www.youtube.com/@handle/live        whatever the channel has live at
#   https://www.youtube.com/channel/UC.../live  the moment the tile is pressed
#
# Env:
#   YT_TARGET   <package>/<activity> of the YouTube app to hand the link to.
#               Default is the Google TV / Android TV client.
#               Fire TV ships a different client, see docs/SIDELOADING.md.
#               Set to "auto" to detect it from a connected device (needs adb_target).
#   SDK_DIR     Android SDK dir, default ~/android_sdk  (see setup_toolchain.sh)
#   ADB         adb binary,      default ~/platform_tools/adb
set -euo pipefail

# ---- target parsing -------------------------------------------------------
# Sets KIND (video|playlist), ID, URL from $1.
parse_target() {
  local t="$1" id=""
  case "$t" in
    *youtube.com/*|*youtu.be/*|*youtube-nocookie.com/*)
      # Channel live page (/@handle/live, /channel/UC.../live): "live" is the last
      # path segment. Kept as a URL so YouTube resolves it to whatever is live now;
      # a 24/7 stream gets a new video id every time it restarts.
      local path="${t%%[?#]*}"; path="${path%/}"
      if [ "${path##*/}" = live ]; then
        local owner="${path%/live}"; owner="${owner##*/}"
        case "$owner" in
          @*)  KIND=live; ID="$owner"; URL="https://www.youtube.com/$owner/live";         return 0 ;;
          UC*) KIND=live; ID="$owner"; URL="https://www.youtube.com/channel/$owner/live"; return 0 ;;
        esac
      fi
      # A list= wins over v=: a watch URL carrying a playlist becomes a playlist
      # tile, which is almost always what someone pasting that link wants.
      id="$(printf '%s' "$t" | grep -oE '[?&]list=[A-Za-z0-9_-]+' | head -1 | cut -d= -f2 || true)"
      if [ -z "$id" ]; then
        id="$(printf '%s' "$t" \
              | grep -oE '(v=|/live/|/shorts/|/embed/|youtu\.be/)[A-Za-z0-9_-]{11}' \
              | head -1 | grep -oE '[A-Za-z0-9_-]{11}$' || true)"
      fi
      [ -n "$id" ] || { echo "could not parse a video or playlist id from: $t" >&2; return 1; }
      ;;
    *) id="$t" ;;
  esac

  case "$id" in
    UC*)                    # channel id -> that channel's uploads playlist
      ID="UU${id#UC}"; KIND=playlist ;;
    PL*|UU*|OL*|RD*|LL*|FL*)
      ID="$id";        KIND=playlist ;;
    *)
      ID="$id";        KIND=video ;;
  esac

  if [ "$KIND" = playlist ]; then
    URL="https://www.youtube.com/playlist?list=$ID"
  else
    URL="https://www.youtube.com/watch?v=$ID"
  fi
}

if [ "${1:-}" = "--print-url" ]; then
  parse_target "${2:?usage: build_shortcut.sh --print-url <target>}"
  echo "$KIND $ID $URL"
  exit 0
fi

TARGET="${1:?usage: build_shortcut.sh <target> <label> [adb_target]}"
LABEL="${2:?usage: build_shortcut.sh <target> <label> [adb_target]}"
ADB_TARGET="${3:-}"
parse_target "$TARGET"

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
[ -x "$BT/aapt2" ]    || { echo "no build-tools under $SDK_DIR, run ./setup_toolchain.sh" >&2; exit 1; }
[ -f "$ANDROID_JAR" ] || { echo "no android.jar under $SDK_DIR, run ./setup_toolchain.sh" >&2; exit 1; }

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

# Ids contain - and _, which are illegal in a java package segment.
PREFIX=v; [ "$KIND" = playlist ] && PREFIX=p; [ "$KIND" = live ] && PREFIX=l
PKG="dev.shift84labs.ytshortcut.$PREFIX$(echo "$ID" | tr -c '[:alnum:]' '_')"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/res/drawable" "$W/src/shortcut" "$W/classes" "$W/dex" "$OUT"

# Playlists and live pages have no thumbnail of their own, so borrow one.
case "$KIND" in
  playlist)   # its first entry
    THUMB_VID="$(curl -fsSL "$URL" \
      | grep -oE '"videoId":"[A-Za-z0-9_-]{11}"' | head -1 | cut -d'"' -f4 || true)"
    [ -n "$THUMB_VID" ] || { echo "could not read playlist $ID, is it public?" >&2; exit 1; } ;;
  live)       # the current stream, or any video on the channel page if nothing is live
    PAGE="$(curl -fsSL -H 'User-Agent: Mozilla/5.0' "$URL" || true)"
    THUMB_VID="$(printf '%s' "$PAGE" \
      | grep -oE '<link rel="canonical" href="[^"]*watch\?v=[A-Za-z0-9_-]{11}' \
      | head -1 | grep -oE '[A-Za-z0-9_-]{11}$' || true)"
    [ -n "$THUMB_VID" ] || THUMB_VID="$(printf '%s' "$PAGE" \
      | grep -oE '"videoId":"[A-Za-z0-9_-]{11}"' | head -1 | cut -d'"' -f4 || true)"
    [ -n "$THUMB_VID" ] || { echo "could not read $URL" >&2; exit 1; } ;;
  *)
    THUMB_VID="$ID" ;;
esac

# mqdefault.jpg is served at exactly 320x180, the Android TV banner size.
curl -fsSL -o "$W/res/drawable/banner.jpg" "https://i.ytimg.com/vi/$THUMB_VID/mqdefault.jpg"

sed -e "s|__URL__|$URL|g" -e "s|__YT_PKG__|$YT_PKG|g" -e "s|__YT_ACT__|$YT_ACT|g" \
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

APK="$OUT/$ID.apk"; [ "$KIND" = live ] && APK="$OUT/live_${ID#@}.apk"
"$BT/zipalign" -f 4 "$W/unsigned.apk" "$W/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:shortcut --ks-key-alias shortcut \
  --out "$APK" "$W/aligned.apk"

echo "built: $APK ($(stat -c%s "$APK") bytes)"
echo "  kind        : $KIND"
echo "  opens       : $URL"
echo "  app package : $PKG"
echo "  via         : $YT_PKG"

if [ -n "$ADB_TARGET" ]; then
  adb_dev install -r "$APK"
  echo "installed to $ADB_TARGET"
fi
