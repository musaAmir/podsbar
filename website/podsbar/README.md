# PodsBar website

Live at **https://musaamir.github.io/podsbar/**, hosted on GitHub Pages.

A buildless, responsive landing page. The deployable files live in `dist/`.

## Make changes

Edit `dist/index.html`, `dist/styles.css`, `dist/app.js`, or the files in `dist/assets/`.
From this directory, preview locally with:

```sh
python3 -m http.server 4173 --directory dist
```

Open http://localhost:4173. No dependencies or build step are required.

## Automatic deployment

Commit and push website changes to `main` in `musaAmir/podsbar`. The
[Pages workflow](../../.github/workflows/pages.yml) checks JavaScript syntax and
publishes only `website/podsbar/dist/`. Changes to the workflow also trigger a
deployment. App-only changes do not redeploy the website.

Watch deployments in [GitHub Actions](https://github.com/musaAmir/podsbar/actions/workflows/pages.yml).
To redeploy the current version without a code change, choose **Run workflow** on
that page and select `main`. Publishing is configured under **Settings → Pages →
Build and deployment → Source: GitHub Actions**. No additional hosting credentials
or repository secrets are required. GitHub provisions HTTPS for the public URL.

## Product content

The product scene is a browser demonstration with illustrative battery readings.
It does not access local Bluetooth devices. Display mode controls and the popover
can be tried directly on the page.

Download links point to the GitHub v1.1.0 release. Update those links and
version-specific installation notes when a new app release is published. The
current release is ad-hoc signed, not Apple-notarized; this is disclosed on the page.

No frameworks, external fonts, analytics, cookies, or runtime dependencies. The
app icon is from the PodsBar project. The product illustration is inline SVG. The
system font stack uses the visitor’s native fonts.

The earlier private Sites preview is separate from GitHub Pages and does not
receive these deployments. GitHub is now the source for the public website.
