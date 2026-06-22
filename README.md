# Firestorm Native Linux Launcher

A native **Linux** launcher for the [Firestorm](https://firestorm-servers.com) World of Warcraft private server — *The War Within* (Dornogal). Install, update, manage addons, and launch the game without the Windows launcher or a Windows VM.

> **Unofficial — community-made.** Not affiliated with, endorsed by, or supported by Firestorm or Blizzard Entertainment. It talks only to Firestorm's **public** launcher API using **your own account**, and you sign in to the game with **your own password** at the normal in-game login screen. It ships no game files and no Firestorm/Blizzard artwork. **Use at your own risk.**

## Download

Grab the latest `.AppImage` from the [**Releases**](https://github.com/szentigrad3/firestorm-native-linux-launcher/releases) page, then:

```bash
chmod +x firestorm-native-linux-launcher-*.AppImage
./firestorm-native-linux-launcher-*.AppImage
```

## Requirements

- A **Proton/Wine runner** — [`umu-run`](https://github.com/Open-Wine-Components/umu-launcher) (recommended) or `wine`. This is the one thing that can't be bundled.
- A modern 64-bit distro (glibc ≥ 2.36).
- **~111 GB** free disk for the TWW client.

The AppImage bundles its own WebKitGTK (for the sign-in window), so you only need a runner.

## Features

- **Sign in** with the real Cloudflare Turnstile, in a native window
- **Install / update / verify / repair** the client — parallel, resumable, hash-checked downloads
- **Addon catalog** — browse, install, and update addons in one click
- **Live news, realm status, and online players**
- Launches via `umu-run`/Proton — pick your Proton build in Settings
- **Manual in-game login** — your account is pre-filled; just type your password

## First run

1. Settings → Game settings: set your install folder (or use Install/Repair to download fresh).
2. Sign in.
3. Press **Play** — the game opens at the WoW login screen with your account filled in; type your password.

## Addons

Browsing the full CurseForge catalog needs a free CurseForge API key. Create one at the [CurseForge console](https://console.curseforge.com/) and paste it into **Settings → Addons**. Without a key, the launcher falls back to a smaller built-in list.

## Notes

- This is the launcher only — it downloads the game from Firestorm's own CDN. No game files are distributed here.
- Firestorm officially supports Windows only; this is a community tool to make their game playable natively on Linux.

## Disclaimer

Unofficial. Not affiliated with or endorsed by Firestorm or Blizzard Entertainment. "World of Warcraft" and related marks belong to their respective owners. Provided as-is, with no warranty. Use at your own risk.
