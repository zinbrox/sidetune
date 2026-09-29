<p align="center">
  <img src="docs/icon.png" width="128" alt="SideTune icon">
</p>

<h1 align="center">SideTune</h1>

<p align="center">
  A floating now-playing player for macOS that lives on the side of your screen.<br>
  Snap it to any edge, tuck it beside the notch, or leave it floating.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-6e56cf" alt="Universal">
  <a href="../../releases/latest"><img src="https://img.shields.io/badge/download-latest-2ea44f" alt="Download"></a>
</p>

<p align="center">
  <img src="docs/hero.png" alt="SideTune docked on the right edge of the screen">
</p>

## Features

- **Any player.** Spotify, Apple Music, browsers, VLC and anything else macOS shows as Now Playing.
- **Drag it anywhere.** A magnet pulls it to edges and corners, and it springs into place.
- **Collapses into a tab.** Docked, it shrinks to a slim tab with the artwork and a live equalizer. Hover it to open the full player, or keep it open all the time.
- **Beside the notch.** Drop it at the top next to the notch and it becomes part of the notch.
- **Pin the app it controls.** By default it follows whatever is playing. Pin Spotify, Music, a browser or any other player and it sticks to that app. A pinned Spotify or Music keeps the controls even when a browser starts playing.
- **Shuffle and repeat** for Spotify and Music.
- **Resizable**, tinted by the album artwork, with lots of small animations.
- **Menu bar mini player** next to battery and Wi-Fi.

<p align="center">
  <img src="docs/demo.gif" width="720" alt="Hovering the tab opens the player, skipping a track, then collapsing">
</p>

<table>
  <tr>
    <td><img src="docs/tab.png" alt="Collapsed tab docked to the edge"></td>
    <td><img src="docs/menubar.png" alt="Menu bar mini player"></td>
  </tr>
  <tr>
    <td align="center">Collapsed tab</td>
    <td align="center">Menu bar mini player</td>
  </tr>
</table>

<p align="center">
  <img src="docs/notch-collapsed.png" alt="Collapsed beside the notch"><br>
  <img src="docs/notch.png" alt="Expanded below the notch">
</p>

<p align="center">
  <img src="docs/sizes.png" alt="Smallest and largest sizes">
</p>

## Installation

1. Download **SideTune-*version*.dmg** from the [latest release](../../releases/latest).
2. Open it and drag **SideTune** into **Applications**.
3. SideTune isn't notarized, so the first time, right-click it in Applications and choose **Open**. Or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SideTune.app
   ```

Requires macOS 14 Sonoma or later.

## Using it

| To | Do this |
| --- | --- |
| Move it | Drag the player |
| Dock it | Drop it near any edge |
| Place it without snapping | Hold <kbd>⌥</kbd> while dragging |
| Put it beside the notch | Drop it at the top, next to the notch |
| Keep it open while docked | Click <kbd>⤢</kbd> on the card |
| Resize | Drag the grip in the card's corner |
| Hide / show | Click <kbd>×</kbd>, throw it off-screen, or press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd> |
| Pin the app it controls | Click the app name on the card and choose an app, or **Automatic** |
| Open the playing app | Click the artwork |

Right-click the menu bar icon for sizes, the notch, and settings.

The first time you pin Spotify or Music, or use shuffle or repeat, macOS asks to let SideTune control that app.

## Building from source

You need the Xcode Command Line Tools and `cmake` (`brew install cmake`). Full Xcode isn't required.

```sh
git clone <this repo>
cd SideTune
scripts/build-app.sh          # → build/SideTune.app
open build/SideTune.app
```

| Script | What it does |
| --- | --- |
| `scripts/test.sh` | Runs the tests |
| `scripts/screenshots.sh` | Renders the images in `docs/` |
| `scripts/release.sh 1.0.0` | Builds the universal `.dmg`, `.zip` and source archive into `dist/` |

## How it works

Since macOS 15.4, only Apple's own apps can read what's playing. SideTune uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), which reads it through the system's `/usr/bin/perl`, the same approach [boring.notch](https://github.com/TheBoredTeam/boring.notch) uses. Pinned Spotify and Music are controlled directly with AppleScript.

## Credits

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by ungive (BSD-3-Clause), bundled in `Vendor/`
- Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch)
