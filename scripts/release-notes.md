# SideTune {{VERSION}}

A floating now-playing player for macOS that docks to the side of your screen, the menu bar, or right beside the notch.

## Highlights

- Works with any player: Spotify, Apple Music, browsers, VLC and more
- Drag anywhere, magnetic snapping to edges and corners, collapses into a slim tab
- Attach beside the notch, or keep it fully open on the side
- Pin the app it controls: pick Spotify, Music, a browser or any other player, and SideTune sticks to it. A pinned Spotify or Music keeps the controls even when something else starts playing
- Shuffle and repeat for Spotify and Music
- Resizable, artwork-tinted, lots of small animations
- Menu bar mini player

## Downloads

| File | What it is |
| --- | --- |
| `SideTune-{{VERSION}}.dmg` | Disk image: open it and drag SideTune to Applications |
| `SideTune-{{VERSION}}.zip` | The app, zipped |
| `SideTune-{{VERSION}}-source.zip` | Source code |

Universal build for Apple Silicon and Intel, macOS 14 Sonoma or later.

## First launch

SideTune isn't notarized, so macOS blocks the first launch. Right-click SideTune in Applications and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/SideTune.app
```

Checksums are in `SHA256SUMS.txt`.
