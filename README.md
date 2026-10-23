


# PodsBar

AirPods battery, right in your Mac’s menu bar.

[Download](https://github.com/musaAmir/podsbar/releases/latest) · [Website](https://musaamir.github.io/podsbar/)

<img src="docs/menubar.png" alt="PodsBar in the macOS menu bar" width="420">

<img src="docs/popover.png" alt="The PodsBar popover: left, right, and case battery tiles, menu bar display options, and settings" width="292">

Free and open source. Requires macOS 14+. Supports Apple silicon and Intel.


See it in action:


https://github.com/user-attachments/assets/190ce860-288c-4ac8-a680-6fd76d6d9c2b



## Install

Download the ZIP, unzip it, and move **PodsBar.app** to **Applications**. Open the app to see your battery levels in the menu bar.

Version 1.2.0 is not notarized by Apple; macOS may block its first launch.

Already on 1.1.0 or later? Choose **Check for Updates…** in the popover to update in place.

## Build

Requires Xcode with Swift 6 or newer.

```sh
swift test
./build.sh
```

[Release guide](docs/updates.md) · [Performance notes](docs/performance.md) · [MIT license](LICENSE)
