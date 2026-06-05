# StayHere Deployment Plan

This plan covers the release, deployment, and update path for StayHere.

The target distribution model is a direct-download macOS app distributed through GitHub Releases. The app is not intended for the Mac App Store because the full feature set depends on Accessibility, Input Monitoring, and private CGS APIs.

## Goals

- Build release artifacts repeatably from source.
- Run common quality, security, and compliance checks before release.
- Publish signed and notarized macOS packages.
- Give users update awareness now without building fragile custom installer logic.
- Keep the update architecture ready for Sparkle once Developer ID signing is available.

## Release Model

StayHere ships as:

- `StayHere.app`
- `StayHere.zip`
- `StayHere.dmg`
- SHA-256 checksum files
- GitHub Release notes generated from `CHANGELOG.md`

Release versions use semantic version tags such as `v1.0.0`. The git tag is the source of truth for `CFBundleShortVersionString`; the short commit SHA or CI run number can be used for `CFBundleVersion`.

The existing scripts remain the packaging entry points:

- `Scripts/build-release-app.sh`
- `Scripts/package-release.sh`

## Step 1 - Prepare The Repo For CI

Add `.github/workflows/ci.yml`.

The CI workflow should run on pull requests and pushes to `main`.

Required jobs:

- Run `swift test`.
- Run `swift build -c release --product StayHereApp`.
- Run a packaging smoke test with ad hoc signing.
- Verify the expected `.app`, `.zip`, and `.dmg` artifacts are produced.

Recommended checks:

- Add Swift formatting or SwiftLint.
- Add shell script linting for files in `Scripts/`.
- Treat compiler warnings as release blockers where practical.

Exit criteria:

- Every pull request proves the app builds and tests.
- Packaging scripts cannot break silently.

## Step 2 - Add Security And Compliance Checks

Enable GitHub repository security features:

- Secret scanning.
- Dependabot alerts.
- Dependency review for pull requests.
- Code scanning if it adds useful signal for this Swift codebase.

Document security-sensitive behavior in `README.md`:

- Why Accessibility is needed.
- Why Input Monitoring is needed.
- Why Automation may be requested.
- Why the app is distributed outside the Mac App Store.
- What private CGS APIs are used for and what risks they carry.

Exit criteria:

- The repo visibly explains the permissions it asks for.
- Releases are gated by automated checks, not only manual inspection.

## Step 3 - Harden Release Builds

Release builds should differ from development builds.

Release behavior:

- Hide Debug menu items unless a user explicitly enables diagnostics.
- Default verbose logging off.
- Keep support logs available but low-noise.
- Use the production bundle identifier.
- Use version and build metadata from the release tag and CI context.

Implementation notes:

- Keep the Debug menu available for development and phase gates.
- Gate release-only behavior with build configuration, an environment value, or a small runtime setting.
- Avoid changing the bundle identifier after users have granted Accessibility or Input Monitoring permissions.

Exit criteria:

- The release app feels like a user-facing product, not a debug artifact.
- Existing diagnostics are still reachable for support.

## Step 4 - Sign, Notarize, And Staple

For public releases, use Apple Developer ID signing.

Required signing flow:

- Import the Developer ID Application certificate into the CI keychain.
- Build the release app.
- Sign with hardened runtime enabled.
- Include only required entitlements.
- Verify the signature with `codesign --verify --deep --strict`.

Required notarization flow:

- Submit the app archive or DMG with `xcrun notarytool`.
- Wait for notarization success.
- Staple the ticket with `xcrun stapler`.
- Verify the stapled artifact with `spctl` and `codesign`.

Secrets needed in GitHub Actions:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD` or App Store Connect API credentials
- Developer ID certificate data
- Developer ID certificate password

Exit criteria:

- A downloaded artifact launches without Gatekeeper bypass steps.
- Notarization failure blocks the release.

## Step 5 - Package Release Artifacts

Use `Scripts/package-release.sh` as the primary packaging command.

The release workflow should produce:

- `dist/StayHere.app`
- `dist/StayHere.zip`
- `dist/StayHere.dmg`
- `dist/StayHere.zip.sha256`
- `dist/StayHere.dmg.sha256`

Recommended script improvements:

- Derive `APP_VERSION` from the git tag.
- Derive `BUILD_NUMBER` from the CI run number or short commit SHA.
- Add checksum generation.
- Add post-build verification for bundle structure and signature.

Exit criteria:

- All release artifacts are produced by automation.
- Artifacts can be verified after download.

## Step 6 - Publish GitHub Releases

Add `.github/workflows/release.yml`.

The release workflow should run on tags matching `v*`.

Workflow stages:

1. Check out the tagged source.
2. Run tests.
3. Build the release app.
4. Sign the app.
5. Package ZIP and DMG.
6. Notarize and staple.
7. Generate checksums.
8. Create or update the GitHub Release.
9. Upload artifacts and checksums.
10. Attach release notes from `CHANGELOG.md`.

Exit criteria:

- Publishing a release is mostly the act of pushing a version tag.
- Manual release steps are limited to approval and final verification.

## Step 7 - Add Update Notifications Now

Before Sparkle, implement a lightweight update checker.

User-facing behavior:

- Add `Check for Updates...` to the menu.
- Add `Update Available...` when a newer version exists.
- Show a non-blocking notice after launch when a newer release is found.
- Open the GitHub Release page or direct download link when the user chooses to update.

Technical behavior:

- Query the latest GitHub Release over HTTPS.
- Compare the latest release tag to the app's current version.
- Use semantic version comparison, not string comparison.
- Cache the last check result and timestamp.
- Respect a user preference for automatic update checks.
- Fail quietly when offline or rate limited.

Suggested Swift structure:

- `UpdateService` protocol.
- `GitHubReleaseUpdateService` implementation.
- `UpdateInfo` model containing version, release URL, download URL, title, notes, and published date.
- `UpdateController` owned by the app delegate or menu controller.
- Shared menu/UI hooks that can later call Sparkle instead.

Out of scope for this stage:

- Do not download and replace the app bundle manually.
- Do not build a custom installer.
- Do not add Sparkle until Developer ID signing and notarized releases are in place.

Exit criteria:

- Users can see that a newer version exists.
- Users can reach the correct release page from the app.
- The code path can later swap from GitHub checks to Sparkle without redesigning the UI.

## Step 8 - Add Sparkle Later

Sparkle becomes the preferred updater after the project has Apple Developer Program membership and Developer ID signing.

Sparkle migration tasks:

- Add Sparkle as a dependency.
- Generate and protect Sparkle update signing keys.
- Add an appcast feed.
- Publish Sparkle-compatible signed update archives.
- Replace `GitHubReleaseUpdateService` with `SparkleUpdateService`.
- Keep the same menu entries and update preferences where possible.

Sparkle release requirements:

- Signed app.
- Notarized release artifact.
- HTTPS appcast feed.
- Verified Sparkle signatures.

Exit criteria:

- Users can check, download, install, and relaunch into updates from inside the app.
- GitHub/manual update flow remains a fallback path if needed.

## Step 9 - Document Install, Update, And Recovery

Add or update user documentation:

- Install from DMG.
- Required permissions.
- Recommended Mission Control settings.
- Update behavior.
- Manual update fallback.
- Uninstall steps.
- Resetting permissions after bundle ID or signing identity changes.
- Supported macOS versions.
- Known limitations for private CGS behavior.

Exit criteria:

- A new user can install, grant permissions, update, and uninstall without guessing.
- Support questions have clear docs to point to.

## Step 10 - Run A Release Dry Run

Before `v1.0.0`, run a full dry release.

Dry run checklist:

- Create a prerelease tag such as `v1.0.0-rc.1`.
- Run the full release workflow.
- Download artifacts from GitHub Releases.
- Verify checksums.
- Install from the DMG on a clean user account or second Mac.
- Confirm the app launches.
- Confirm permission prompts and onboarding work.
- Confirm update checks detect a newer mocked or prerelease version.
- Confirm logs are quiet in release mode.
- Confirm uninstall and rollback docs are accurate.

Exit criteria:

- The real release has already been rehearsed end to end.
- Any release blockers are fixed before the public tag.

## Step 11 - Publish The First Public Release

Release checklist:

- Confirm all phase gates are approved.
- Confirm `CHANGELOG.md` has release notes for the version.
- Confirm CI is green on `main`.
- Create and push the final tag, such as `v1.0.0`.
- Let the release workflow publish artifacts.
- Download the release from GitHub.
- Verify launch, signature, notarization, and checksums.
- Mark the GitHub Release as public and ready.

Exit criteria:

- Users can download a signed, notarized release.
- Users are informed about future versions through the in-app update check.
- The next release follows the same repeatable path.

## Implementation Order

1. Add CI validation.
2. Add security and compliance checks.
3. Harden release behavior in the app.
4. Improve packaging verification and checksum generation.
5. Add signing, notarization, and stapling.
6. Add GitHub Release publishing.
7. Add GitHub-based update notifications.
8. Add install, update, and recovery docs.
9. Run a prerelease dry run.
10. Publish `v1.0.0`.
11. Add Sparkle after Developer ID signing is available.

## Definition Of Done

The release system is complete when:

- Pull requests run tests and release-build checks.
- Public artifacts are signed, notarized, stapled, packaged, and checksummed.
- GitHub Releases are produced from version tags.
- Users can see when a newer version exists.
- Documentation covers install, permissions, updates, recovery, and limitations.
- Sparkle has a clear future integration path without replacing the update UI.
