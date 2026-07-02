# Releasing Portfolix for macOS

This document describes the expected release flow for GitHub Releases.

## Source of Truth

Use this repository as the single source of truth for development and release preparation. Make changes directly here, keep each work batch inspectable with Git, and validate with the Swift test suite before packaging.

## Release Modes

### Local ad hoc DMG

Useful for packaging checks only:

```bash
./scripts/package-release-dmg.sh
```

This creates an ad hoc signed app and DMG under `../release`. It is not suitable for public distribution because Gatekeeper will not treat it as a trusted Developer ID build.

### Signed and notarized DMG

Requires Apple Developer Program membership and a Developer ID Application certificate:

```bash
xcrun notarytool store-credentials portfolix-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

PORTFOLIX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
PORTFOLIX_NOTARY_PROFILE="portfolix-notary" \
./scripts/package-release-dmg.sh
```

The script signs nested code first, signs the app bundle with hardened runtime, creates a DMG, signs the DMG, submits it for notarization, and staples the notarization ticket.

## GitHub Release Checklist

1. Update version and build number.
2. Run `swift test`.
3. Build signed and notarized DMG.
4. Verify signature and notarization:

```bash
codesign -dvvv --entitlements :- ../release/Portfolix.app
spctl -a -vv ../release/Portfolix.app
spctl -a -vv ../release/Portfolix-0.1.0.dmg
```

5. Create a Git tag.
6. Draft a GitHub Release from the tag.
7. Upload the notarized `.dmg` as a release asset.
8. Include checksums in the release notes.

## Credentials

Never commit certificates, private keys, `.p12` files, app-specific passwords, notary profiles, or API keys.
