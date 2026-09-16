# Troubleshooting

Every failure below was hit while building this, not imagined.

## Quick table

| Symptom | Cause | Fix |
|---|---|---|
| App chooser appears instead of playback | Several packages claim `youtube.com` URLs | Pin the intent, set `YT_TARGET` correctly |
| Tile does nothing, no error on screen | Missing `<queries>` → `ActivityNotFoundException` | Already handled; if you edited the manifest, restore it |
| Tile shows a generic placeholder icon | Only `android:banner` set, not `android:icon` | Set both |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Rebuilt with a different keystore | Reuse the original `shortcut_keystore.jks`, or `adb uninstall` first |
| `screencap` returns a black frame | Video surface is not captured | Verify with `dumpsys media_session` |
| `adb pair` hangs forever | Used the connect port, or the code expired | Re-read both ports, keep the pairing screen open |
| `sdkmanager` download 404s | Stale cmdline-tools build number | Skip it, resolve names from `repository2-3.xml` |
| `aapt add -q` → "Unknown flag" | `aapt` v1 has no `-q`, unlike `aapt2` | Drop the flag |
| Tile launches YouTube but plays nothing | The video was deleted or went private, or a live stream ended (24/7 streams restart under new ids) | Rebuild against the channel's live address, or a playlist |
| Tile missing from home screen | Appended to the end of the apps row | Scroll right; use Reorder / Move to Front |
| Cannot reach the device after a reboot | Wireless debugging ports rotate | Re-pair. Installed tiles are unaffected |

---

## An app chooser appears instead of the video

The most common failure, and the reason this project exists.

Google TV devices ship **three** packages that all claim `youtube.com` URLs:

```
com.google.android.youtube.tv
com.google.android.youtube.tvunplugged
com.google.android.youtube.tvmusic
```

Confirm it:

```bash
adb shell cmd package resolve-activity -a android.intent.action.VIEW \
  -d "https://www.youtube.com/watch?v=<video_id>"
```

If that prints `com.android.internal.app.ResolverActivity`, the intent is unpinned and the system is asking the user to choose.

On **Fire TV** this shows up differently: the Google package does not exist at all, so a default-target build falls back to the chooser (or to nothing, if no app claims the URL). Rebuild with `YT_TARGET=auto` or Amazon's package.

## The tile launches YouTube but nothing plays

The app opens and you get **"Something went wrong - This live stream recording is not available"**, or a blank video page. `dumpsys media_session` shows no session for YouTube at all.

The target itself is gone. Most often:

- a **live stream ended** and the creator did not keep the recording. "24/7" streams do this routinely: they are back-to-back long streams, and each restart gets a new video id
- the video was deleted or set to private
- the video became region-locked

Confirm from any machine, no TV needed:

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<video_id>&format=json"
```

`404` means it is gone outright. Note that a **200 does not mean it is playable**: an ended live stream keeps its oEmbed metadata while the recording itself is unavailable.

The watch page HTML has the real state:

```bash
curl -s -H "User-Agent: Mozilla/5.0" "https://www.youtube.com/watch?v=<video_id>" \
  | grep -oE '"isLiveNow":(true|false)|"playabilityStatus":\{"status":"[A-Z_]+"|"endTimestamp":"[^"]+"' \
  | sort -u
```

`UNPLAYABLE` plus an `endTimestamp` is an ended stream.

**The fix is to stop pointing at a single video id.**

For a live channel, build against its live address, which YouTube resolves to whatever is live when the tile is pressed:

```bash
./build_shortcut.sh "https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx/live" "Label" <ip>:<port>
```

For recorded content, build against a playlist, or a channel's uploads playlist, which keeps working as its contents change:

```bash
./build_shortcut.sh UCxxxxxxxxxxxxxxxxxxxxxx "Label" <ip>:<port>
```

Then remove the dead tile:

```bash
adb uninstall dev.shift84labs.ytshortcut.v<video_id>
```

## The tile installs but does nothing when pressed

Almost always Android 11+ package visibility. Since Android 11, an app cannot see or start another package unless it declares it:

```xml
<queries>
    <package android:name="com.google.android.youtube.tv" />
</queries>
```

Without it, `setClassName()` throws `ActivityNotFoundException`. The template handles this, and the `<queries>` entry is substituted with whatever `YT_TARGET` you built with, so the two can never drift apart.

Check the logs while pressing the tile:

```bash
adb logcat -d | grep -iE "ytshortcut|ActivityNotFound"
```

## INSTALL_FAILED_UPDATE_INCOMPATIBLE

```
Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package ... signatures
do not match newer version; ignoring!]
```

The package is already installed, signed with a different key. Android will not upgrade across a signature change. Either restore the original `shortcut_keystore.jks`, or remove the old tile:

```bash
adb uninstall dev.shift84labs.ytshortcut.v<video_id>
```

This is easy to hit by building the same video from a fresh clone, since a new keystore is generated on first run.

## adb pair hangs and never returns

Two causes, in order of likelihood:

1. **Wrong port.** The pairing port and the connect port are different, and both are displayed on the same settings screen. `adb pair` against the connect port hangs rather than erroring.
2. **Expired code.** The pairing code is invalidated the moment you navigate away from the pairing dialog.

Sanity-check reachability first:

```bash
ping -c2 <tv_ip>
(echo > /dev/tcp/<tv_ip>/<pairing_port>) && echo OPEN
```

## The build fails

| Error | Meaning |
|---|---|
| `no build-tools under ...` | Run `./setup_toolchain.sh` |
| `no android.jar under ...` | Same |
| `YT_TARGET must be <package>/<activity>` | Missing the `/activity` half |
| `could not detect a YouTube app` | `YT_TARGET=auto` found no known client; set it manually |
| `curl: (22) ... 404` on the banner | Bad video id, or the video has no thumbnail. Check the id is exactly 11 characters |

## Nothing here matches

Open an issue with:

```bash
adb shell getprop ro.build.version.release
adb shell getprop ro.product.model
adb shell pm list packages | grep -i youtube
```
