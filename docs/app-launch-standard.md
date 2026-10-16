# App launch standard

PodsBar is the reference for future Mac app launches. Keep each app’s identity and purpose; reuse the release process and visual language.

## App readiness

- Fix reproducible bugs, broken flows, and obvious missing essentials before adding features.
- Check launch, settings, errors, permissions, sleep/wake, and supported Macs as relevant.
- Measure memory and background work. Prefer native APIs, bounded caches, and event-driven updates; avoid unnecessary polling and dependencies.
- Run relevant tests and distinguish automated checks from hardware verification.

## Distribution

- Use the app’s GitHub repository, a minimal README, and downloadable versioned releases.
- Integrate Sparkle with an app-specific update feed and signing key. Keep private keys outside source control.
- Include update checks, a manual check, and clear user control over installation.
- Sign and notarize public Mac downloads with Developer ID. Label any ad-hoc development build accurately.
- Verify the packaged download and update signatures before publication. Document the next-release procedure.

## Website style

| Element | PodsBar baseline |
| --- | --- |
| Background | Warm off-white `#f8f7f4` |
| Text | Charcoal `#242527`; secondary `#747471` |
| Borders | Subtle `#deddd8` |
| Accent | Muted green; soft peach, pink, and blue product backdrops |
| Typography | Native system fonts; large, tightly spaced headings |
| Header | 76 px desktop, 64 px mobile |
| Layout | Maximum width 1120 px; generous whitespace |
| Controls | Dark pill buttons; visible keyboard focus |
| Panels | Approximately 24–26 px corner radius |

Use a short product headline, a clear Mac download button, an honest product preview, a few useful features, and concise installation FAQs. Use each app’s actual capabilities and screenshots; label illustrative demos. Avoid fabricated metrics, testimonials, or unsupported performance claims.

Reference implementation: [PodsBar website](../website/podsbar/dist/index.html) and [styles](../website/podsbar/dist/styles.css).

## Publishing

Use lightweight static pages and GitHub Pages where suitable. Deploy automatically from `main` when website files change, with a manual deployment option. Verify the public HTTPS page, assets, and download links. Keep the README short and link to detailed documentation separately.
