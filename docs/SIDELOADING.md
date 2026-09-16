# Sideloading the APK

The build produces a normal Android TV app at `out/<video_id>.apk`. Getting it onto a device is the same problem as sideloading anything else, so any method you already use will work. Below are the paths per platform.

Whatever the method: once installed, the tile is permanent. It survives reboots and power loss, and never needs the PC again.

---

## Table of contents

- [Google TV and Android TV](#google-tv-and-android-tv) - onn, Chromecast, Shield, TCL, Hisense, Sony
- [Fire TV](#fire-tv) - Stick, Cube, Fire TV Edition
- [Vizio](#vizio) - why this cannot work
- [Roku, Samsung, LG](#roku-samsung-lg) - same answer as Vizio
- [Method A: ADB over the network](#method-a-adb-over-the-network)
- [Method B: Downloader app](#method-b-downloader-app-no-pc)
- [Method C: USB drive](#method-c-usb-drive)
- [Finding the tile afterwards](#finding-the-tile-afterwards)

---

## Google TV and Android TV

Covers the onn 4K and 4K Pro, Chromecast with Google TV, Nvidia Shield, Mi Box, and TCL / Hisense / Sony / Philips sets running Android TV.

**No configuration needed.** The default `YT_TARGET` is already the Google TV YouTube client.

```bash
./build_shortcut.sh <video_id> "<Label>" <ip>:<port>
```

Use [Method A](#method-a-adb-over-the-network), [B](#method-b-downloader-app-no-pc) or [C](#method-c-usb-drive) to install.

### Verify the target on your specific device

Device makers occasionally ship a different YouTube build. To check what yours actually has:

```bash
adb shell pm list packages | grep -i youtube
adb shell cmd package resolve-activity --brief \
  -c android.intent.category.LEANBACK_LAUNCHER com.google.android.youtube.tv
```

The second command prints `package/activity`, which is exactly the `YT_TARGET` format. Or just let the script do it: `YT_TARGET=auto`.

---

## Fire TV

Covers Fire TV Stick (all generations), Fire TV Cube, and Fire TV Edition televisions from Toshiba, Insignia and Amazon's own Omni series.

Fire OS is Android underneath, so sideloading works. **But Amazon ships its own YouTube client**, `com.amazon.firetv.youtube`, and the Google TV package does not exist on the device. Build with the default target and the tile will fall back to a chooser instead of playing.

### 1. Find the activity name

Connect via ADB (below) and ask the device:

```bash
adb shell pm list packages | grep -i youtube
adb shell cmd package resolve-activity --brief \
  -c android.intent.category.LEANBACK_LAUNCHER com.amazon.firetv.youtube
```

Or skip it entirely and let the script detect it:

```bash
YT_TARGET=auto ./build_shortcut.sh <video_id> "<Label>" <ip>:5555
```

### 2. Enable ADB on Fire TV

Settings → **My Fire TV** → **Developer options** → **ADB debugging** on, and **Apps from Unknown Sources** on.

If Developer options is missing (newer Fire OS hides it): Settings → My Fire TV → About → click **Fire TV Stick** 7 times.

Fire TV uses **classic ADB on port 5555**, not the pair-code flow:

```bash
adb connect <fire_tv_ip>:5555
```

Accept the prompt on screen. Find the IP under Settings → My Fire TV → About → Network.

### 3. Build and install

```bash
YT_TARGET=auto ./build_shortcut.sh <video_id> "<Label>" <fire_tv_ip>:5555
```

### Fire TV home screen caveat

Sideloaded apps land in **Your Apps & Channels**, usually at the end of the row. Open that row, highlight the tile, press the **Menu** (three lines) button and choose **Move to Front**.

Amazon's launcher deprioritises sideloaded apps and reserves the top rows for sponsored content. If that annoys you, a third-party launcher such as Firestarter or Wolf Launcher gives sideloaded apps first-class placement. That is outside the scope of this project.

---

## Vizio

**This cannot be done on a Vizio TV.** Not with a workaround, not with a USB stick, not with developer mode.

SmartCast (now branded VIZIO OS) is Vizio's own platform. It is not Android, has no "unknown sources" setting, no ADB, and no mechanism to install an APK. Apps arrive only from Vizio's own store and platform updates. Guides claiming otherwise are describing Android TVs, or are simply wrong.

Your options on a Vizio set:

- **Cast it.** Open the video on your phone and cast/AirPlay to the TV. This gets the video playing but is not a home-screen tile, and needs the phone every time.
- **Add a cheap Android TV device.** An onn 4K box or a Fire TV Stick is roughly $20-$30 and makes everything in this repo work. This is the only route to an actual tile.

---

## Roku, Samsung, LG

Same answer as Vizio, for the same reason. Roku OS, Samsung Tizen and LG webOS are all closed, non-Android platforms with no sideloading path for ordinary users. Publishing a real channel/app through each vendor's developer program is a completely different (and much larger) undertaking.

---

## Method A: ADB over the network

Works on every Android TV and Fire TV device. Best when you are already building on a computer.

### Fire TV and older Android TV: classic ADB

```bash
adb connect <tv_ip>:5555
adb install -r out/<video_id>.apk
```

### Android 11+ Google TV: wireless debugging with pairing

Newer Google TV devices (including the onn 4K Pro) use a pair-code flow. On the TV: Settings → System → Developer options → **Wireless debugging**.

> **There are two different `ip:port` pairs on that screen and mixing them up is the most common failure.**
> - The **main** Wireless debugging screen shows the **connect** port.
> - **Pair device with pairing code** shows a **different** pairing port plus a 6-digit code.

```bash
adb pair    <tv_ip>:<pairing_port> <6_digit_code>
adb connect <tv_ip>:<connect_port>
adb install -r out/<video_id>.apk
```

The pairing code expires the instant you leave that screen, so keep it open. Both ports rotate on every reboot, so expect to re-pair before a future build. Already-installed tiles are unaffected.

To unlock Developer options in the first place: Settings → System → About → click **Android TV OS build** 7 times.

---

## Method B: Downloader app (no PC)

Good when the TV and the computer are not conveniently on the same desk, or when you want someone non-technical to install it.

1. Install **Downloader** (by AFTVnews) from the Play Store or Amazon Appstore.
2. Enable sideloading:
   - Google TV: Settings → System → Developer options → **Install unknown apps** → allow Downloader
   - Fire TV: Settings → My Fire TV → Developer options → **Apps from Unknown Sources** → allow Downloader
3. Host the APK somewhere the TV can reach: a GitHub release URL, a LAN web server, or any file host.
4. Type the URL into Downloader and let it download, then choose Install.

Note that Downloader cannot fetch from URLs requiring authentication, so a private repo release link will not work. Use a public URL or a LAN share.

---

## Method C: USB drive

1. Copy the APK to a USB drive.
2. Install a file manager on the TV (**X-plore File Manager** and **File Commander** both work).
3. Plug in the drive, allow unknown sources for the file manager, browse to the APK and install.

This is the only option on devices with no network access, and it works on Fire TV and Android TV alike. Chromecast with Google TV needs a powered USB-C hub.

---

## Finding the tile afterwards

New apps are appended to the **end** of the apps row, past everything already installed.

| Platform | Where | How to move it |
|---|---|---|
| Google TV | Home → **Apps** → scroll the *Your apps* row right | **Reorder** button at the end of the row |
| Android TV (older) | Apps row on the home screen | Long-press the tile → Move |
| Fire TV | **Your Apps & Channels** | Highlight → **Menu** button → *Move to Front* |

If the tile does not appear at all, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
