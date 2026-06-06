# Packaging Scripts

These scripts turn the SwiftPM executable target into a distributable macOS app bundle and release artifacts.

## Build the `.app`

```bash
Scripts/build-release-app.sh
```

Useful overrides:

```bash
Scripts/build-release-app.sh \
  --app-name StayHere \
  --bundle-id com.tha.stayhere \
  --version 1.0.0 \
  --identity "Developer ID Application: Your Name (TEAMID)"
```

## Build ZIP + DMG

```bash
Scripts/package-release.sh
```

This writes artifacts into `dist/` by default:

- `dist/StayHere.app`
- `dist/StayHere.zip`
- `dist/StayHere.dmg`
- `dist/StayHere.zip.sha256`
- `dist/StayHere.dmg.sha256`

The packaging script derives release metadata when it can:

- `APP_VERSION` comes from the current git tag when the checkout is on a release tag like `v1.2.3`.
- `BUILD_NUMBER` comes from `GITHUB_RUN_NUMBER`, then `GITHUB_SHA`, then the short git commit SHA.
- The app bundle is verified after build, before the ZIP and DMG are created.

## Signing

If you provide `--identity`, the scripts sign the bundle with hardened runtime enabled.
If you do not, the scripts still ad hoc sign the app by default so the bundle has a real signature for local testing.
Use `--no-sign` only if you explicitly want an unsigned bundle.

If you change the bundle identifier or signing identity, macOS will treat it like a different app and you may need to re-grant Accessibility permissions in System Settings.
