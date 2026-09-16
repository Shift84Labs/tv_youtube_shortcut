# tv_youtube_shortcut

Put a tile on your TV's home screen that opens **one specific YouTube video, playlist or channel**, instantly, with no navigating, searching or scrolling.

Hand it a link and a label, and it builds a ~25 KB Android TV app whose entire job is to fire one intent and exit. Install it once and it behaves like any other app on the home screen: it survives reboots, needs no PC, no network pairing and no companion service.

Built for a toddler who wants the same thing every time and cannot read a search box. Works just as well for a workout playlist, a fireplace loop, a livestream, or white noise.

```bash
./setup_toolchain.sh                                            # one time
./build_shortcut.sh dQw4w9WgXcQ "Never Gonna"                   # a video
./build_shortcut.sh UCG2CL6EUjG8TVT1Tpl9nJdg "Ms Rachel"        # a whole channel
```

Then sideload the APK. See **[docs/SIDELOADING.md](docs/SIDELOADING.md)** for your device.

---

## Why an app, and not just ADB

The obvious approach is to enable ADB and fire an intent. That launches the video, but it is a *command*, not a shortcut, and it fails as a solution for two reasons:

1. **TV launchers only show apps that declare a `LEANBACK_LAUNCHER` intent filter.** There is no user-facing way to pin an arbitrary deep link to the home screen. A real tile has to be an installed package.
2. **Wireless debugging does not survive a reboot**, and its ports rotate every time. Anything driven by an ADB command from a PC breaks on every power cycle.

An APK sidesteps both. ADB is only involved at install time, and only if you choose to install that way.

---

## Videos, playlists and channels

> [!TIP]
> **Prefer a playlist or a channel over a single video.** A single video can be deleted, go private, or, in the case of a livestream, simply end. When that happens the tile still launches YouTube but shows *"This live stream recording is not available"* and plays nothing. A playlist keeps working as its contents change, and a channel's uploads playlist refills itself every time the creator posts.

`<target>` accepts any of these:

| You pass | You get |
|---|---|
| `dQw4w9WgXcQ` | That one video |
| `PLxxxx…` / `UUxxxx…` | That playlist, starting at its first entry |
| `UCxxxx…` (a channel id) | That channel's uploads playlist, i.e. everything it posts |
| `https://www.youtube.com/watch?v=…` | The video |
| `https://www.youtube.com/live/…` | The stream |
| `https://youtu.be/…`, `/shorts/…`, `/embed/…` | The video |
| `https://www.youtube.com/playlist?list=…` | The playlist |
| `https://www.youtube.com/watch?v=…&list=…` | The **playlist**, not the single video |

That last row is deliberate. If a URL carries a `list=`, you almost certainly want the playlist tile.

Playlist and channel tiles start at the first entry and continue through it. To find a channel id, open the channel page and search the HTML for `externalId`, or just paste any of its video URLs and use the playlist form instead.

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
./build_shortcut.sh <target> <label> [adb_target]
./build_shortcut.sh --print-url <target>          # show how a target parses, build nothing
```

| Argument | Meaning |
|---|---|
| `target` | A video id, playlist id, channel id, or any YouTube URL (see above) |
| `label` | Text shown under the tile, e.g. `"Ms Rachel"` |
| `adb_target` | Optional `ip:port`. If given, the APK is installed over ADB after building |

| Environment variable | Default | Purpose |
|---|---|---|
| `YT_TARGET` | Google TV client | `<package>/<activity>` to hand the link to. Use `auto` to detect it from a connected device |
| `SDK_DIR` | `~/android_sdk` | Where build-tools and platforms live |
| `ADB` | `~/platform_tools/adb` | adb binary |

Examples:

```bash
# a single video, build only
./build_shortcut.sh dQw4w9WgXcQ "Never Gonna"

# an entire channel's uploads, built and installed over the network
./build_shortcut.sh UCG2CL6EUjG8TVT1Tpl9nJdg "Ms Rachel" 192.168.1.50:5555

# paste a URL straight from the address bar
./build_shortcut.sh "https://www.youtube.com/playlist?list=PLxxxx" "Bedtime" 192.168.1.50:5555

# Fire TV: let the script work out the right client from the device itself
YT_TARGET=auto ./build_shortcut.sh PLxxxx "Workouts" 192.168.1.50:5555
```

Each target gets its own package name derived from its id, so any number of tiles coexist.

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

## Tests

```bash
./test_parse.sh
```

Covers target parsing: bare ids, every URL shape, playlist-beats-video precedence, channel-to-uploads conversion, and that an unparseable URL fails loudly instead of building a broken tile.

## Prebuilt example

The [Releases](../../releases) page has a prebuilt example APK so you can try the mechanism without setting up a toolchain. It opens the Ms Rachel uploads playlist and targets the Google TV client. For your own target, build your own - it takes one command.

## Notes on signing

The build generates a throwaway self-signed keystore on first run and reuses it. Nothing depends on who signed it, but Android refuses to upgrade a package whose signature changed, so keep `shortcut_keystore.jks` if you want to update tiles in place. It is gitignored.

## License

MIT, see [LICENSE](LICENSE).
