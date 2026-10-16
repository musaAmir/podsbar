---
format: 1920x1080
duration: 15s
message: "Your AirPods battery, one glance away in the menu bar"
arc: Hook → Problem → Glance → Name
audience: Mac users with AirPods
mode: autonomous
music: none
beat_grid: "133.3 BPM, first beat 0.128s, bars at 0 / 1.928 / 3.728 / 5.528 / 7.328 / 9.128 / 10.928 / 12.728; final hit 13.63s"
---

## Frame 1 — Hook

- scene: "How much battery is left?" — kinetic question, a scrambling ??% counter
- duration: 3.728s
- transition_in: cut
- status: animated
- src: compositions/frames/01-hook.html
- blueprint: compose
- asset_candidates: none
- focal: kinetic type

Scene 1 (0.0–1.2s): dark canvas, dot grid, green glow breathing. "Your AirPods" words rise in with blur → Scene 2 (1.2–2.4s): line swaps (cut-the-curve) to "are at…" and a giant "??%" slot counter scrambles digits → Scene 3 (2.4–3.4s): counter keeps scrambling, slow push-in.

## Frame 2 — The old way

- scene: Click. Open. Squint. — three steps it takes today, struck through
- duration: 1.8s
- transition_in: cut
- status: animated
- src: compositions/frames/02-problem.html
- blueprint: compose
- asset_candidates: none
- focal: kinetic type

Scene 1 (0.0–1.8s): three words punch in one by one on the beat ("Click." "Open." "Squint."), each with a small macOS glyph (cursor, Control Center toggle, magnifier) → Scene 2 (1.8–3.0s): a red strike line draws through all three; "Every time." fades in under them.

## Frame 3 — One glance

- scene: The real PodsBar menu bar glyph in big 3D, capsules fill, popover drops down
- duration: 5.4s
- transition_in: cut
- status: animated
- src: compositions/frames/03-glance.html
- blueprint: compose
- asset_candidates: none (rebuilt vector menu bar + popover from MenuBarIcon.swift / PopoverView)
- focal: menu bar glyph

Scene 1 (0.0–1.6s): a huge glass macOS menu bar slides down tilted in 3D; the PodsBar glyph "88L ▯▮ R84" sits big in it; capsules fill from empty while numbers count up 0→88 / 0→84 → Scene 2 (1.6–3.2s): camera eases flatter; "One glance." headline types in to the left with "glance" in green → Scene 3 (3.2–5.2s): popover drops from the glyph (Left 88%, Right 84%, Case 100% bars filling), slight parallax drift.

## Frame 4 — PodsBar

- scene: App icon pops with glow, PodsBar wordmark, tagline and chips
- duration: 4.072s
- transition_in: cut
- status: animated
- src: compositions/frames/04-cta.html
- blueprint: compose
- asset_candidates: assets/app-icon.png
- focal: app icon

Scene 1 (0.0–1.0s): app icon scales up from 0.6 with a green ring pulse → Scene 2 (1.0–2.0s): "PodsBar" wordmark slides out from behind the icon; tagline "AirPods battery in your menu bar." → Scene 3 (2.0–3.4s): chips "macOS 14+", "Open source", "No tracking" stagger in; final settle.

## Video direction

Dark, Apple-keynote-meets-SaaS-ad. Fast kinetic type in frames 1–2, then the product gets air in frame 3. One accent color (battery green). Motion: expo/back eases, blur-in entrances, 3D perspective on the UI, continuous slow camera push so nothing freezes.
