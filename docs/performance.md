# Performance notes

## Memory check — 2026-10-15

Measured on the development Mac with release builds of the original commit (`6383456`)
and the revised app, both native release builds compiled with the same Swift 6.4 toolchain. Both were launched
by their app-bundle executables, allowed to complete their initial Bluetooth scan,
and sampled while idle, before opening either popover.

| Build | Physical footprint (`footprint`) |
| --- | ---: |
| Original source | 61.1 MB |
| Revised AppKit status-item host | 31.7 MB |
| With the Sparkle updater integrated (later sample) | 33.6 MB |

These are samples in decimal MB, not memory ceilings. The revised build also showed
0.0% CPU in the idle `ps` sample. It still performs brief Bluetooth scans and responds
to system events. RSS includes shared and reclaimable pages and was higher than the
physical footprint; these values should not be mixed when comparing builds.

The Sparkle sample used a universal release bundle relocated outside the build directory,
with automatic update checking enabled. Its app bundle was about 4.3 MB on disk. This was
an additional sample, not a simultaneous controlled comparison of the updater overhead.

The main memory change is avoiding a persistent SwiftUI menu-bar scene and creating
the popover only on demand. Closing the popover releases its hosting controller and
view graph. Framework caches may remain, so memory after opening the popover can
be higher than the pre-open figures above. No post-open peak measurement was obtained.

Desktop UI automation was unavailable during this pass. The running app and real
Bluetooth reader were smoke-tested, but popover appearance and keyboard behavior
still need a manual check before publication. Intel was cross-compiled, not run;
macOS 14 was the deployment target, not the system used for these measurements.

## Resource bounds

- One in-flight scan, with a 10-second `system_profiler` report timeout and a separate
  15-second process deadline. Timeout or cancellation terminates the owned child.
- At most 1 MiB of buffered report output, read in 16 KiB chunks without a blocked
  worker thread. JSON parsing occurs away from the main actor. The output limit is
  not a cap on the memory used by the child process or the parsed JSON objects.
- One one-shot polling timer, with 25% tolerance, armed after a scan completes.
- One replaceable delayed connection refresh. Device-event bursts do not accumulate
  sleeping tasks, and a follow-up that falls during a scan is handled on completion.
- Polls and delayed refreshes are cancelled during system sleep and app shutdown.
- One cached status image. Unchanged device arrays are not republished.
- No repeating freshness timer in the popover.
- Sparkle manages one daily update-check schedule. Checks can be disabled in the popover;
  updates are not downloaded or installed automatically by default. Its unused sandbox
  XPC services are omitted. System profiling is disabled.

## Reproduce

Build with `./build.sh` and launch `build/PodsBar.app`. Use Activity Monitor's Memory
column or `footprint -p PID` for the physical footprint. Compare builds using the same
OS, compiler, hardware, connected devices, elapsed time, and popover state.

For a longer check, sample before opening the popover, after opening/closing it
repeatedly, and after several polls and sleep/wake cycles. Watch for sustained growth
rather than requiring the allocator to immediately return every cached page.
