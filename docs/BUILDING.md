# Building

## Toolchain

```bash
./setup_toolchain.sh
```

Fetches into your home directory:

```
~/platform_tools/          adb
~/android_sdk/
├── build-tools/<rel>/     aapt, aapt2, d8, zipalign, apksigner
└── platforms/android-34/  android.jar
```

Override locations with `SDK_DIR` and `TOOLS_DIR`. A JDK must already be present; the script checks and tells you how to install one.

### Why not Gradle or Android Studio

Gradle would pull hundreds of megabytes plus a wrapper per project to produce the same 25 KB file. The whole pipeline here is six commands. For a single activity with no dependencies, no resources beyond one image, and no `R` class, a build system is pure overhead.

### Why not sdkmanager

`commandline-tools-linux-<build>_latest.zip` returns **404** as soon as its build number goes stale, and there is no stable "latest" alias. The setup script skips `sdkmanager` entirely and resolves real archive names from Google's own manifest:

```bash
curl -fsSL -o repo.xml https://dl.google.com/android/repository/repository2-3.xml
grep -oE 'build-tools_r[0-9]+(\.[0-9]+)*-linux\.zip' repo.xml | sort -V | tail -1
grep -oE 'platform-34[a-z0-9._-]*\.zip'              repo.xml | sort -V | tail -1
```

Then downloads those two zips directly from `dl.google.com`. No licence prompts, no interactive steps, no Java-based package manager in the middle.

> Note: build-tools unpacks into a directory named for its **release** (e.g. `android-14`), which is *not* the API level. The build script globs for it rather than assuming a name.

---

## What the build does

For each shortcut, in a temp directory:

| Step | Command | Purpose |
|---|---|---|
| 1 | `curl i.ytimg.com/vi/<id>/mqdefault.jpg` | Fetch the tile image |
| 2 | `sed` on the templates | Substitute video id, label, package, target |
| 3 | `aapt2 compile` | Compile resources |
| 4 | `aapt2 link` | Build the resource table + binary manifest |
| 5 | `javac` | Compile the single activity against `android.jar` |
| 6 | `d8` | Convert class files to `classes.dex` |
| 7 | `aapt add` | Insert the dex into the APK |
| 8 | `zipalign` | 4-byte align |
| 9 | `apksigner` | Sign with a local throwaway key |

No `R.java` is generated, because the Java source never references a resource. Only the manifest does, via `@drawable/banner`.

### Target parsing

`<target>` is normalised before anything is built. A bare id is used as-is; a URL is
scraped for `list=` first and `v=` / `/live/` / `/shorts/` / `/embed/` / `youtu.be/`
second, so a watch URL carrying a playlist becomes a playlist tile. A channel id
(`UC…`) is rewritten to its uploads playlist (`UU…`) by swapping the two-character
prefix, which is a documented YouTube convention and needs no API call.

Inspect the result without building:

```bash
./build_shortcut.sh --print-url "https://www.youtube.com/watch?v=abc&list=PLxyz"
# playlist PLxyz https://www.youtube.com/playlist?list=PLxyz
```

`./test_parse.sh` asserts all of the above, including that an unparseable YouTube
URL exits non-zero rather than quietly building a tile that goes nowhere.

### The icon

A playlist has no thumbnail of its own, so the build fetches the playlist page and
uses its **first entry's** thumbnail. That is one `curl` and one `grep`, and it means
a channel tile shows whatever that channel posted most recently at build time.

`https://i.ytimg.com/vi/<video_id>/mqdefault.jpg` is served at **exactly 320x180**, which is the Android TV banner size. That means no image library, no resizing step, and no dependency on ImageMagick or Pillow.

The manifest sets both `android:banner` and `android:icon` to it. Older Android TV launchers draw the 320x180 banner; the current Google TV launcher draws a **circular icon with a text label underneath** and centre-crops the image, so roughly the middle third of the thumbnail is what shows. If a particular thumbnail crops badly, drop a square 512x512 PNG at `template/res/drawable/banner.png` and remove the `curl` line.

### Signing

First run generates `shortcut_keystore.jks`, self-signed, 30-year validity, password `shortcut`. None of that is a secret and nothing depends on who signed it; Android simply refuses to install an unsigned package.

**Keep the keystore.** Android will not upgrade a package whose signing certificate changed. If you lose it, you must `adb uninstall` each tile before reinstalling. The file is gitignored so it never reaches the repo.

---

## Generated app

One activity, translucent theme, no UI:

```java
Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(URL));
i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
i.setClassName(YT_PKG, YT_ACT);   // pin it, or the chooser appears
startActivity(i);
finish();
```

Two manifest details carry the whole design:

```xml
<!-- Android 11+ package visibility. Without this, setClassName into another
     package throws ActivityNotFoundException and the tile silently does nothing. -->
<queries>
    <package android:name="__YT_PKG__" />
</queries>
```

```xml
<!-- This is what makes it appear on a TV home screen at all. -->
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
</intent-filter>
```

`minSdkVersion` is 21 and `targetSdkVersion` is 34, passed on the `aapt2 link` command line rather than written into the manifest.

---

## Verifying a build without a screen

`adb exec-out screencap -p` returns an **all-black frame** during video playback, because the video surface is not captured. That is not a failure, and it will mislead you if you trust it.

Use the media session instead, which also gives you the title:

```bash
adb shell dumpsys media_session | grep -A12 "package=com.google.android.youtube.tv" \
  | grep -E "state=PlaybackState|metadata:"
```

```
state=PlaybackState {state=PLAYING(3), position=46800296, ...}
metadata: size=5, description=Learn with Ms Rachel - Toddler Learning - ...
```

For a genuine end-to-end test, force-stop YouTube first and confirm the new task id differs, which proves the tile drove the launch rather than a leftover session:

```bash
adb shell am force-stop com.google.android.youtube.tv
adb shell am start -n <shortcut_pkg>/shortcut.MainActivity
sleep 10
adb shell dumpsys activity activities | grep topResumedActivity
```
