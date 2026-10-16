# Updates and releases

PodsBar uses [Sparkle 2](https://sparkle-project.org/documentation/) and the public
[musaAmir/podsbar GitHub repository](https://github.com/musaAmir/podsbar).

The app checks this stable address once a day, or when the user asks:

```text
https://github.com/musaAmir/podsbar/releases/latest/download/appcast.xml
```

Each stable GitHub release must include **both** the final app ZIP and `appcast.xml`.
The appcast points to that version's immutable `/releases/download/vVERSION/` ZIP URL.
Publish the draft as the latest stable release. Pre-releases are not part of this feed.
GitHub will return 404 at the feed address until the first such release is published.

Users may disable automatic checks. Downloads and installation require user approval by
default; Sparkle's update dialog offers its own automatic-install option. System profiling
is disabled. The app validates signed feeds and verifies archive signatures before extraction.
Markdown notes are embedded in the signed feed, avoiding an extra release-notes download.

Apps released before this integration cannot acquire Sparkle remotely. Those users need
to manually download the first Sparkle-enabled version once.

## One-time setup

### Update key — configured on this Mac

A dedicated Sparkle Ed25519 key was generated in the login Keychain with the account:

```text
com.amirmusa.podsbar.sparkle
```

`Resources/Info.plist` contains its **public** key as `SUPublicEDKey`. The private key
is not in the repository. Keep this public key in subsequent versions.

Verify that the current Mac has the matching key:

```sh
./scripts/setup-updates.sh
```

Back up the private key to a secure location outside this repository. Sparkle documents
its Keychain [export/import options](https://sparkle-project.org/documentation/#eddsa-ed25519-signatures).
For example, after choosing a protected backup location:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.amirmusa.podsbar.sparkle -x /secure/location/PodsBar-update-key
```

Treat that export as a release credential. On a replacement Mac, restore it with `-f`
instead of generating a new key. `setup-updates.sh` only verifies the configured key;
it deliberately does not generate a replacement when the expected key is missing.
Never put a private key, Apple signing certificate export, or notarization password in Git.
The signing test uses an unrelated disposable key and does not need the real release key.

### Apple signing and notarization — recommended for distribution

This Mac had Apple Development identities, but no **Developer ID Application** identity
when the integration was implemented. For a notarized public release, obtain a Developer ID
Application certificate through your Apple Developer account and install it with its
private key in Keychain. Apple's
[distribution guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
covers this setup. An Apple Development certificate or ad-hoc signature is not a substitute.

Check installed signing identities:

```sh
security find-identity -v -p codesigning
```

Create a notarytool Keychain profile interactively, using your Apple Developer credentials:

```sh
xcrun notarytool store-credentials PodsBar
```

The command asks for the required account information. Credentials stay in Keychain.
The release scripts refer to the profile by name rather than accepting passwords.
Xcode command-line tools, Python 3, and the authenticated GitHub CLI (`gh`) are needed.

## Prepare a release

Write a Markdown notes file, commit the source and notes, and choose a new display version
and a strictly increasing integer build number. Example values:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="PodsBar"
./scripts/prepare-release.sh 1.1.0 2 ReleaseNotes/1.1.0.md
```

The version and notes path above are examples, not a release that has been published.
Every release, even a small fix, needs a larger build number. Keep the bundle identifier
`com.amirmusa.podsbar` stable. `CFBundleVersion` determines whether Sparkle offers an update.

The preparation script:

1. Verifies the configured Keychain key and fetches and verifies the previous signed feed
   when one exists. It refuses a reused or lower build number.
2. Builds a universal app, embeds Sparkle, removes its unused sandbox XPC services, and
   signs helpers, framework, and app with the same identity, from the inside out.
3. Submits a temporary archive to Apple's notary service and waits for acceptance.
4. Staples and validates the ticket, verifies nested code signatures, and assesses Gatekeeper.
5. Creates the final ZIP **after stapling**, generates and signs the appcast, embeds the
   Markdown notes, and verifies the feed and archive signatures and metadata.
6. Writes the result to `build/releases/v1.1.0/`, including checksums and the source commit.

No release is uploaded by this command. The preparation script requires a clean working
tree so a release tag can point to the exact source that was built. It refuses to overwrite
an existing prepared version. Failed preparation cleans its temporary signing/archive files;
inspect notarization failures with `xcrun notarytool log SUBMISSION_ID --keychain-profile PodsBar`.

## Upload and publish

First test the prepared, notarized app, including an actual update from an older test
installation, all display modes, keyboard navigation, and launch at login. Use an isolated
Mac/account for update-installation tests so your everyday installation is not replaced.
A separate test feed/build can be used as described in
[Sparkle's testing instructions](https://sparkle-project.org/documentation/#6-test-sparkle-out).

If Developer ID signing is not available, an explicitly ad-hoc release can be prepared:

```sh
./scripts/prepare-release.sh --adhoc 1.1.0 2 ReleaseNotes/1.1.0.md
```

This mode skips Apple notarization and Gatekeeper assessment, while still signing and
verifying the Sparkle archive and feed. It adds a prominent signing notice to the GitHub
and in-app release notes and records `ad-hoc` in the release metadata. macOS may block
the first launch of the downloaded app. The default mode continues to require Developer
ID signing and successful notarization.

Then upload the prepared files as a draft:

```sh
./scripts/publish-release.sh v1.1.0
```

This verifies the prepared checksums and signatures, uploads all assets, and targets the
recorded source commit. It refuses an existing Git tag. Review the draft on GitHub and
publish it as the latest stable release. Once published, existing Sparkle-enabled apps
can discover it through the stable feed URL. Automatic discovery may take up to a day;
**Check for Updates…** starts a check immediately.

Do not replace a published ZIP or edit a signed appcast. Prepare a new version and build
number for corrections. The next feed retains previous items, including releases with
older macOS requirements. Delta updates are disabled to keep the release process and
asset list small; the full ZIP is only a few megabytes.

## Local verification

```sh
swift test -Xswiftc -warnings-as-errors
python3 -m unittest discover -s Tests/ReleaseScripts
./build.sh release universal
./Tests/ReleaseScripts/smoke-sparkle.sh
```

The smoke test creates a throwaway key and a copied app, verifies a real signed feed and
archive, and checks that modifying a download URL or archive fails signature validation.
It removes those test files and never reads or exports the production private key.
CI runs these checks without release credentials and does not upload or publish anything.

The integration has been built and a relocated app bundle has been launched successfully.
Developer ID notarization and an actual public update installation remain untested until
the certificate, notary profile, and first release are available. Desktop UI automation
was unavailable during implementation, so the update controls and dialogs also need a
manual check before publication.
