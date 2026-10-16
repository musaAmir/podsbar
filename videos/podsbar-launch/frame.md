---
version: alpha
name: PodsBar Night — Frame
description: >
  Bespoke dark SaaS-launch look for PodsBar. Near-black graphite canvas from the app icon,
  white Inter display type with tight negative tracking, the icon's battery green as the only
  accent (fills, glows, the single highlighted word). macOS-native glass surfaces
  (blurred translucent panels, 1px white hairlines at 10%, 18–22px radii). Depth from soft
  green radial glows and a faint dot grid, never hard shadows.
unit: the frame — 1920×1080
principle: one accent · type does the shouting · UI is the hero

colors:
  canvas: "#0B0C0F"
  surface: "#16171B"
  glass: "rgba(30,31,36,0.72)"
  hairline: "rgba(255,255,255,0.10)"
  ink: "#F5F5F7"
  ink-muted: "#8E8E93"
  ink-faint: "#48484A"
  accent: "#5BD87A"
  accent-glow: "rgba(91,216,122,0.35)"
  danger: "#FF453A"

radii:
  panel: "22px"
  card: "16px"
  pill: "999px"

typography:
  display: { fontFamily: "Inter", px: 150, weight: 800, lineHeight: 0.95, tracking: "-0.055em", color: "ink" }
  h1:      { fontFamily: "Inter", px: 96, weight: 700, lineHeight: 1.0, tracking: "-0.045em", color: "ink" }
  h2:      { fontFamily: "Inter", px: 56, weight: 600, lineHeight: 1.1, tracking: "-0.03em", color: "ink" }
  body:    { fontFamily: "Inter", px: 30, weight: 500, lineHeight: 1.4, color: "ink-muted" }
  chip:    { fontFamily: "Inter", px: 24, weight: 600, tracking: "-0.01em", color: "ink" }

components:
  glass-panel:
    background: "{colors.glass}"
    border: "1px solid {colors.hairline}"
    rounded: "{radii.panel}"
    backdrop: "blur(30px) saturate(1.6)"
  glow:
    background: "radial-gradient(circle, {colors.accent-glow}, transparent 65%)"
  dot-grid:
    background: "radial-gradient(rgba(255,255,255,0.07) 1px, transparent 1px) 0 0 / 36px 36px"
---
