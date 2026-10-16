# PodsBar

AirPods battery, right in your Mac’s menu bar.

[Download](https://github.com/musaAmir/podsbar/releases/latest) · [Website](https://musaamir.github.io/podsbar/)

<img src="docs/menubar.png" alt="PodsBar in the macOS menu bar" width="420">

Free and open source. Requires macOS 14+. Supports Apple silicon and Intel.


See it in action:


https://github.com/user-attachments/assets/4e9e4c1c-df37-4c14-bd9a-b653186aa67c



## Install

Download the ZIP, unzip it, and move **PodsBar.app** to **Applications**. Open the app to see your battery levels in the menu bar.

Version 1.1.0 is not notarized by Apple; macOS may block its first launch.

## Build

Requires Xcode with Swift 6 or newer.

```sh
swift test
./build.sh
```

[Release guide](docs/updates.md) · [Performance notes](docs/performance.md) · [MIT license](LICENSE)
