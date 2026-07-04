# Portfolix Auto Update

Portfolix uses Sparkle 2 for macOS app updates.

## Runtime Flow

1. Sparkle reads `SUFeedURL` and `SUPublicEDKey` from the app bundle.
2. Portfolix starts `SPUStandardUpdaterController` only when both values exist.
3. The app probes update availability once per 24 hours and shows the sidebar update hint when Sparkle finds a valid update.
4. The menu item `Check for Updates...` / `检查更新...` opens Sparkle's standard update UI.
5. Sparkle downloads the update, validates the EdDSA signature, and installs it after the user approves relaunch.

## One-Time Key Setup

Generate the Sparkle EdDSA key once:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Keep the private key safe in Keychain. The current public key embedded in release builds is:

```text
BX7U6Nmwk+IBB5lluFk8rJ3KFopJfeYJS7DFOR+wqZM=
```

## Release Flow

1. Build the release DMG with `scripts/package-release-dmg.sh`.
2. Upload the DMG and `.sha256` file to the GitHub Release tag, for example `v0.1.2`.
3. Generate and update `appcast.xml`:

```bash
PORTFOLIX_VERSION=0.1.2 scripts/generate-sparkle-appcast.sh
```

4. Commit and push the updated `appcast.xml`.

The default feed URL is:

```text
https://raw.githubusercontent.com/S4kur4/Portfolix/main/appcast.xml
```

The default download URL prefix used for appcast generation is:

```text
https://github.com/S4kur4/Portfolix/releases/download/v$PORTFOLIX_VERSION/
```

## Security Notes

- Do not commit the private EdDSA key.
- The public EdDSA key is intentionally committed through the app bundle metadata.
- Prefer Developer ID signing and notarization for public releases.
- Keep update downloads on HTTPS.
- Do not manually edit a signed appcast after generation; regenerate it instead.
