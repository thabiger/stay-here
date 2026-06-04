# Packaging Scripts

These scripts turn the SwiftPM executable target into a distributable macOS app bundle and release artifacts.

## Build the `.app`

```bash
Scripts/build-release-app.sh
```

Useful overrides:

```bash
Scripts/build-release-app.sh \
  --app-name NamedSpaces \
  --bundle-id com.yourcompany.NamedSpaces \
  --version 1.0.0 \
  --identity "Developer ID Application: Your Name (TEAMID)"
```

## Build ZIP + DMG

```bash
Scripts/package-release.sh
```

This writes artifacts into `dist/` by default:

- `dist/NamedSpaces.app`
- `dist/NamedSpaces.zip`
- `dist/NamedSpaces.dmg`

## Signing

If you provide `--identity`, the scripts sign the bundle with hardened runtime enabled.
If you do not, the scripts still ad hoc sign the app by default so the bundle has a real signature for local testing.
Use `--no-sign` only if you explicitly want an unsigned bundle.

If you change the bundle identifier or signing identity, macOS will treat it like a different app and you may need to re-grant Accessibility and Input Monitoring permissions in System Settings.
