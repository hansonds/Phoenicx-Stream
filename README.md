<p align="center"><img src="assets/logo.png" width="120"></p>

<h1 align="center">Phoenicx Stream</h1>

<p align="center">Play your <b>TorBox</b> library on Android phones, Android TV / Fire TV and Windows — arranged like a streaming app with <b>TMDB</b> posters, seasons and episodes. No server needed.</p>

---

## Features

- Reads everything in your TorBox account (torrents, usenet and web downloads)
- Matches files to TMDB: posters, backdrops, ratings, descriptions, seasons and episode names
- Movies, TV Shows, Recently Added, Continue Watching, Search
- Built-in mpv player: MKV, HEVC, HDR, DTS, TrueHD, Atmos tracks, embedded subtitles — no transcoding
- Audio and subtitle track picker, resume where you stopped, auto-plays the next episode
- Works with touch, mouse/keyboard and TV remote (D-pad)
- Your API keys stay on your device

## Download

Go to **Releases** and pick:

| Device | File |
|---|---|
| Android phone / Android TV (64-bit) | `PhoenicxStream-x.y.z-arm64.apk` |
| Fire TV Stick (4K, 4K Max, Lite) | `PhoenicxStream-x.y.z-armv7-FireTV.apk` |
| Not sure | `PhoenicxStream-x.y.z-universal.apk` |
| Windows 10/11 | `PhoenicxStream-x.y.z-Windows-x64-portable.zip` → run `PhoenicxStream.exe` |

## First start

1. **TorBox key** — torbox.app → Settings → API Key
2. **TMDB key** — themoviedb.org → Settings → API (the "API Key" or the "API Read Access Token")
3. Press **Save & connect**

## Remote controls (TV)

| Button | While playing |
|---|---|
| OK | Show controls |
| Left / Right | Back 10 s / Forward 30 s |
| Play/Pause | Play / Pause |
| Back | Hide controls, then exit |

Windows: Space = play/pause, F or double-click = full screen, Esc = exit.

## Building

GitHub builds everything: **Actions → Build Phoenicx Stream → Run workflow**, enter a version. The APKs and the Windows zip appear in **Releases**.

---

Made by **Hanson D**. This product uses the TMDB API but is not endorsed or certified by TMDB.
