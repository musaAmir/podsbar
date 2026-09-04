# PodsBar

AirPods battery in the macOS menu bar. Each bud is a capsule that fills up, with its own
percentage next to it.

<img src="docs/menubar.png" alt="PodsBar in the menu bar" width="420">

<img src="docs/popover.png" alt="PodsBar popover" width="260">

## Install

macOS 14+.

```
./build.sh
cp -R build/PodsBar.app /Applications/
```

Open it once from /Applications, then tick **Launch at login**.

## Why

Older AirPods menu bar apps read `BatteryPercentLeft` / `BatteryPercentRight` from the IOKit
registry. Those keys no longer exist — the whole service is gone from `ioreg`, and battery
state now lives in `bluetoothd`. Apps built that way don't error, they just quietly show
nothing.

PodsBar reads `system_profiler SPBluetoothDataType` instead, once a minute.

## Notes

- No permissions. Nothing here touches a TCC-protected API, so there's no Bluetooth prompt.
- No Dock icon.
- Refreshes on connect, on wake, and when you open it.
- Case shows `—` when the buds are out of the case. macOS doesn't know it then either.

## Licence

MIT
