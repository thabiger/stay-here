#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Create release packaging artifacts for the macOS app.

Usage:
  Scripts/package-release.sh [options]

Options:
  --app-name NAME           App bundle name. Default: StayHere
  --target-name NAME        SwiftPM executable target name. Default: StayHereApp
  --bundle-id ID            Bundle identifier. Default: com.tha.stayhere
  --version VERSION         CFBundleShortVersionString. Default: 0.1.0
  --build-number NUMBER     CFBundleVersion. Default: git short SHA or 1
  --output-dir DIR          Directory for packaging outputs. Default: dist
  --identity ID             Codesign identity. If omitted, the bundle is ad hoc signed.
  --no-sign                 Skip codesigning entirely.
  --entitlements FILE       Entitlements plist to pass to codesign when signing.
  --no-zip                  Skip ZIP creation.
  --no-dmg                  Skip DMG creation.
  --no-clean                Keep the existing output directory contents.
  -h, --help                Show this help.

Environment:
  APP_NAME, TARGET_NAME, BUNDLE_ID, APP_VERSION, BUILD_NUMBER, OUTPUT_DIR,
  CODESIGN_IDENTITY, ENTITLEMENTS_PATH
EOF
}

APP_NAME="${APP_NAME:-StayHere}"
TARGET_NAME="${TARGET_NAME:-StayHereApp}"
BUNDLE_ID="${BUNDLE_ID:-com.tha.stayhere}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-}"
SIGN_MODE="adhoc"
MAKE_ZIP=1
MAKE_DMG=1
CLEAN_OUTPUT=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --target-name)
            TARGET_NAME="$2"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --version)
            APP_VERSION="$2"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --identity)
            CODESIGN_IDENTITY="$2"
            SIGN_MODE="identity"
            shift 2
            ;;
        --no-sign)
            SIGN_MODE="none"
            shift
            ;;
        --entitlements)
            ENTITLEMENTS_PATH="$2"
            shift 2
            ;;
        --no-zip)
            MAKE_ZIP=0
            shift
            ;;
        --no-dmg)
            MAKE_DMG=0
            shift
            ;;
        --no-clean)
            CLEAN_OUTPUT=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

package_dir="$OUTPUT_DIR"
app_bundle="$package_dir/$APP_NAME.app"
zip_path="$package_dir/$APP_NAME.zip"
dmg_path="$package_dir/$APP_NAME.dmg"

if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    rm -rf "$app_bundle" "$zip_path" "$dmg_path"
fi
mkdir -p "$package_dir"

build_args=(
    --app-name "$APP_NAME"
    --target-name "$TARGET_NAME"
    --bundle-id "$BUNDLE_ID"
    --version "$APP_VERSION"
    --output-dir "$package_dir"
)

if [[ -n "$BUILD_NUMBER" ]]; then
    build_args+=(--build-number "$BUILD_NUMBER")
fi
if [[ -n "$CODESIGN_IDENTITY" ]]; then
    SIGN_MODE="identity"
fi
if [[ "$SIGN_MODE" == "identity" ]]; then
    build_args+=(--identity "$CODESIGN_IDENTITY")
elif [[ "$SIGN_MODE" == "none" ]]; then
    build_args+=(--no-sign)
fi
if [[ -n "$ENTITLEMENTS_PATH" ]]; then
    build_args+=(--entitlements "$ENTITLEMENTS_PATH")
fi
if [[ $CLEAN_OUTPUT -eq 0 ]]; then
    build_args+=(--no-clean)
fi

"$repo_root/Scripts/build-release-app.sh" "${build_args[@]}"

if [[ $MAKE_ZIP -eq 1 ]]; then
    ditto -c -k --keepParent "$app_bundle" "$zip_path"
    echo "Created $zip_path"
fi

if [[ $MAKE_DMG -eq 1 ]]; then
    temp_dmg="$package_dir/.${APP_NAME}.tmp.dmg"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$app_bundle" \
        -ov \
        -format UDZO \
        "$temp_dmg"
    mv "$temp_dmg" "$dmg_path"
    echo "Created $dmg_path"
fi

echo "$app_bundle"
