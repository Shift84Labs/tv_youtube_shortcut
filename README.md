# tv_youtube_shortcut

Put a tile on your TV's home screen that opens **one specific YouTube video**, instantly, with no navigating, searching or scrolling.

Hand it a video id and a label, and it builds a ~25 KB Android TV app whose entire job is to fire one intent and exit. Install it once and it behaves like any other app on the home screen: it survives reboots, needs no PC, no network pairing and no companion service.

Built for a toddler who wants the same video every time and cannot read a search box. Works just as well for a workout video, a fireplace loop, a livestream, or a white-noise track.

```bash
./setup_toolchain.sh                                    # one time
./build_shortcut.sh dQw4w9WgXcQ "Never Gonna"           # builds out/dQw4w9WgXcQ.apk
```

Then sideload the APK. See **[docs/SIDELOADING.md](docs/SIDELOADING.md)** for your device.

---

## Why an app, and not just ADB

The obvious approach is to enable ADB and fire an intent. That launches the video, but it is a *command*, not a shortcut, and it fails as a solution for two reasons:

1. **TV launchers only show apps that declare a `LEANBACK_LAUNCHER` intent filter.** There is no user-facing way to pin an arbitrary deep link to the home screen. A real tile has to be an installed package.
2. **Wireless debugging does not survive a reboot**, and its ports rotate every time. Anything driven by an ADB command from a PC breaks on every power cycle.

An APK sidesteps both. ADB is only involved at install time, and only if you choose to install that way.

---

## Device compatibility

| Platform | Works | Notes |
|---|---|---|
| **Google TV** (onn 4K / 4K Pro, Chromecast with Google TV, TCL, Hisense, Sony) | Yes | Default target, no configuration needed |
| **Android TV** (Nvidia Shield, Mi Box, older Sony / Philips / Sharp) | Yes | Default target |
| **Fire TV** (Stick, Cube, Fire TV Edition sets by Toshiba / Insignia / Omni) | Yes | Amazon ships its **own** YouTube client, so you must set `YT_TARGET`. See [docs/SIDELOADING.md](docs/SIDELOADING.md#fire-tv) |
| **Vizio SmartCast / VIZIO OS** | **No** | Not Android. No sideloading of any kind, by design |
| **Roku** | **No** | Not Android, no sideloading |
| **Samsung Tizen / LG webOS** | **No** | Not Android, no sideloading |

> Anything not running Android under the hood is out of reach. There is no APK-shaped hole in Roku, Tizen, webOS or SmartCast. The workaround for those is a $30 Android TV stick, not a clever build flag.

---

## Requirements

- A Linux, WSL or macOS box to build on
- A JDK (17 is fine) - `setup_toolchain.sh` checks and tells you how to install one
- `curl` and `unzip`

`setup_toolchain.sh` fetches `adb`, Android build-tools and one `android.jar` into your home directory. **No Gradle, no Android Studio, no `sdkmanager`.** Roughly 300 MB, one time.

---

## Usage

```
./build_shortcut.sh <video_id> <label> [adb_target]
```

| Argument | Meaning |
|---|---|
| `video_id` | The 11-character id, e.g. `dQw4w9WgXcQ` |
| `label` | Text shown under the tile, e.g. `"Ms Rachel"` |
| `adb_target` | Optional `ip:port`. If given, the APK is installed over ADB after building |

The video id is the part after `v=`, or after `/live/`, or after `youtu.be/`. Tracking parameters like `?si=...` are not needed.

| Environment variable | Default | Purpose |
|---|---|---|
| `YT_TARGET` | Google TV client | `<package>/<activity>` to hand the video to. Use `auto` to detect it from a connected device |
| `SDK_DIR` | `~/android_sdk` | Where build-tools and platforms live |
| `ADB` | `~/platform_tools/adb` | adb binary |

Examples:

```bash
# Google TV / Android TV, build only
./build_shortcut.sh dQw4w9WgXcQ "Never Gonna"

# build and install over the network
./build_shortcut.sh dQw4w9WgXcQ "Never Gonna" 192.168.1.50:5555

# Fire TV
YT_TARGET=com.amazon.firetv.youtube/com.amazon.firetv.youtube.MainActivity \
  ./build_shortcut.sh dQw4w9WgXcQ "Never Gonna" 192.168.1.50:5555

# let the script work out the right client from the device itself
YT_TARGET=auto ./build_shortcut.sh dQw4w9WgXcQ "Never Gonna" 192.168.1.50:5555
```

Each video gets its own package name derived from its id, so any number of tiles coexist.

---

## The one thing that trips everybody up

Google TV devices ship **three** packages that all claim `youtube.com` URLs:

```
com.google.android.youtube.tv
com.google.android.youtube.tvunplugged     (YouTube TV)
com.google.android.youtube.tvmusic         (YouTube Music)
```

A plain `ACTION_VIEW` intent therefore resolves to the system chooser and asks the user to pick an app, which defeats the entire point. The generated app pins the intent with `setClassName()` and declares a matching `<queries>` entry so Android 11+ package visibility does not block it.

If the pinned package is wrong for the device, the app falls back to an unpinned intent so you get a chooser rather than a tile that does nothing.

---

## Documentation

- **[docs/SIDELOADING.md](docs/SIDELOADING.md)** - installing the APK on Google TV, onn, Fire TV, and generic Android TV, plus why Vizio/Roku cannot
- **[docs/BUILDING.md](docs/BUILDING.md)** - toolchain setup, what the build actually does, why there is no Gradle
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - every failure mode hit while building this, with fixes

## Prebuilt example

The [Releases](../../releases) page has a prebuilt example APK so you can try the mechanism without setting up a toolchain. It is hardcoded to one specific children's video and targets the Google TV client, so it is a demo of the *shape* of the thing. For your own video, build your own.

## Notes on signing

The build generates a throwaway self-signed keystore on first run and reuses it. Nothing depends on who signed it, but Android refuses to upgrade a package whose signature changed, so keep `shortcut_keystore.jks` if you want to update tiles in place. It is gitignored.

## License

MIT, see [LICENSE](LICENSE).
