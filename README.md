# SideTune

A floating now-playing player for macOS that docks to the side of your screen instead of the notch.

- **Always on top**, on every Space, and optionally over full-screen apps. Never steals focus.
- **Drag it anywhere.** Near an edge it's magnetically pulled in, and on release it springs into place and collapses into a slim tab. Hover the tab to expand it.
- **Throw it off-screen** or press × to hide it. Bring it back with **⌥⌘M**, the menu bar icon, or by opening the app again.
- **Works with any player** (Spotify, Music, browsers, VLC…) through the system's now-playing info.
- **Pin a source.** Pin Spotify or Music and the controls stay on that app, even if a browser starts playing.
- **Menu bar icon** next to battery and Wi-Fi, with a mini player (click) and a menu (right-click).

## Build

Needs only the Xcode Command Line Tools and `cmake` (`brew install cmake`).

```sh
scripts/build-app.sh          # → build/SideTune.app (release)
scripts/build-app.sh debug
open build/SideTune.app
```

Move it to `/Applications` if you want "Launch at login" to work.

```sh
scripts/test.sh               # snapping/geometry + source routing tests
scripts/preview.sh [art.png]  # renders UI states to build/preview/*.png
```

`scripts/swiftc.sh` calls `swiftc` directly because SwiftPM is broken on some Command Line Tools installs. It also works around a known duplicate `SwiftBridging` modulemap in those installs, using a VFS overlay rather than editing system files.

## How it gets now playing

Since macOS 15.4, only Apple-entitled processes may read MediaRemote. SideTune bundles [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause, in `Vendor/`). The adapter runs the system `/usr/bin/perl` with a small helper framework and streams now-playing JSON. It's the same approach boring.notch uses.

Pinned Spotify and Music are controlled with AppleScript. The first time you pin one, macOS asks for Automation permission. Other apps can be pinned too, but the system only lets anyone control the *current* now-playing app, so those controls only work while that app is the active player.

## Layout

```
Sources/SideTune/
  App/        entry point, settings, global hotkey
  Window/     panel, window spring, drag/dock/hover controller, snapping math
  Media/      adapter stream, AppleScript players, routing/pinning
  UI/         card, tab, shared components, theme
  MenuBar/    status item, mini player, source menu
  Settings/   settings window
```
