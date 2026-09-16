#!/usr/bin/env bash
# Checks target parsing: bare ids, full URLs, playlists, channels.
# Run: ./test_parse.sh
set -uo pipefail
B="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_shortcut.sh"
fail=0

check() { # check <target> <expected "kind id url">
  local got; got="$("$B" --print-url "$1" 2>&1)"
  if [ "$got" = "$2" ]; then
    printf 'ok   %-52s -> %s\n' "$1" "$got"
  else
    printf 'FAIL %-52s\n       expected: %s\n       got     : %s\n' "$1" "$2" "$got"
    fail=1
  fi
}

V=https://www.youtube.com/watch?v
P=https://www.youtube.com/playlist?list

check 'dQw4w9WgXcQ'                                  "video dQw4w9WgXcQ $V=dQw4w9WgXcQ"
check "$V=dQw4w9WgXcQ"                               "video dQw4w9WgXcQ $V=dQw4w9WgXcQ"
check 'https://youtu.be/dQw4w9WgXcQ'                 "video dQw4w9WgXcQ $V=dQw4w9WgXcQ"
check 'https://www.youtube.com/live/C7HWHvOsW78?si=x' "video C7HWHvOsW78 $V=C7HWHvOsW78"
check 'https://www.youtube.com/shorts/dQw4w9WgXcQ'   "video dQw4w9WgXcQ $V=dQw4w9WgXcQ"
check 'PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ'           "playlist PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ $P=PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ"
check "$P=PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ"        "playlist PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ $P=PLbpi6ZahtOH4NHDkCyGBGKnF8Rdr8gNfJ"
# a channel id resolves to that channel's uploads playlist
check 'UCG2CL6EUjG8TVT1Tpl9nJdg'                     "playlist UUG2CL6EUjG8TVT1Tpl9nJdg $P=UUG2CL6EUjG8TVT1Tpl9nJdg"
# list= must win over v=: pasting a watch-in-playlist URL should build a playlist tile
check "$V=dQw4w9WgXcQ&list=PLtest123"                "playlist PLtest123 $P=PLtest123"

# channel live pages stay URLs, so the tile follows stream restarts
L=https://www.youtube.com
check "$L/@msrachel/live"                            "live @msrachel $L/@msrachel/live"
check "$L/@msrachel/live?si=abc"                     "live @msrachel $L/@msrachel/live"
check "$L/channel/UCG2CL6EUjG8TVT1Tpl9nJdg/live/"    "live UCG2CL6EUjG8TVT1Tpl9nJdg $L/channel/UCG2CL6EUjG8TVT1Tpl9nJdg/live"
# ...but /live/<video id> is still a single video
check "$L/live/jBvzOfT8_44?si=xyz"      "video jBvzOfT8_44 $V=jBvzOfT8_44"

# garbage must fail loudly rather than build a broken tile
if "$B" --print-url 'https://www.youtube.com/feed/subscriptions' >/dev/null 2>&1; then
  echo "FAIL unparseable youtube URL should have errored"; fail=1
else
  echo "ok   unparseable youtube URL rejected"
fi

[ $fail -eq 0 ] && echo "PASS" || echo "FAILURES"
exit $fail
