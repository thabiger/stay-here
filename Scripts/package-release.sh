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
APP_VERSION="${APP_VERSION:-}"
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

strip_version_prefix() {
    local value="$1"

    if [[ "$value" == v* ]]; then
        printf '%s\n' "${value#v}"
    else
        printf '%s\n' "$value"
    fi
}

derive_app_version() {
    local tag_name

    if [[ -n "${APP_VERSION:-}" ]]; then
        printf '%s\n' "$APP_VERSION"
        return 0
    fi

    if [[ -n "${GITHUB_REF_TYPE:-}" && "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME:-}" == v* ]]; then
        strip_version_prefix "$GITHUB_REF_NAME"
        return 0
    fi

    if git describe --tags --exact-match >/dev/null 2>&1; then
        tag_name="$(git describe --tags --exact-match)"
        if [[ "$tag_name" == v* ]]; then
            strip_version_prefix "$tag_name"
            return 0
        fi
    fi

    if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME:-}" == v* ]]; then
        strip_version_prefix "$GITHUB_REF_NAME"
        return 0
    fi

    printf '%s\n' "0.1.0"
}

derive_build_number() {
    if [[ -n "${BUILD_NUMBER:-}" ]]; then
        printf '%s\n' "$BUILD_NUMBER"
        return 0
    fi

    if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
        printf '%s\n' "$GITHUB_RUN_NUMBER"
        return 0
    fi

    if [[ -n "${GITHUB_SHA:-}" ]]; then
        printf '%s\n' "${GITHUB_SHA:0:7}"
        return 0
    fi

    if git rev-parse --short HEAD >/dev/null 2>&1; then
        git rev-parse --short HEAD
        return 0
    fi

    printf '%s\n' "1"
}

write_sha256() {
    local artifact_path="$1"
    local checksum_path="$2"
    local checksum_value

    if command -v shasum >/dev/null 2>&1; then
        checksum_value="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
        checksum_value="$(sha256sum "$artifact_path" | awk '{print $1}')"
    else
        echo "Missing required tool: shasum or sha256sum" >&2
        return 1
    fi

    printf '%s  %s\n' "$checksum_value" "$(basename "$artifact_path")" > "$checksum_path"
    echo "Created $checksum_path"
}

verify_app_bundle() {
    local bundle_path="$1"
    local executable_path="$bundle_path/Contents/MacOS/$APP_NAME"
    local info_plist="$bundle_path/Contents/Info.plist"

    test -d "$bundle_path"
    test -x "$executable_path"
    test -f "$info_plist"

    if [[ "$SIGN_MODE" != "none" ]]; then
        codesign --verify --deep --strict --verbose=2 "$bundle_path"
    fi
}

package_dir="$OUTPUT_DIR"
app_bundle="$package_dir/$APP_NAME.app"
zip_path="$package_dir/$APP_NAME.zip"
dmg_path="$package_dir/$APP_NAME.dmg"
zip_checksum_path="$zip_path.sha256"
dmg_checksum_path="$dmg_path.sha256"

if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    rm -rf "$app_bundle" "$zip_path" "$dmg_path" "$zip_checksum_path" "$dmg_checksum_path"
fi
mkdir -p "$package_dir"

APP_VERSION="$(derive_app_version)"
BUILD_NUMBER="$(derive_build_number)"

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
verify_app_bundle "$app_bundle"

if [[ $MAKE_ZIP -eq 1 ]]; then
    ditto -c -k --keepParent "$app_bundle" "$zip_path"
    echo "Created $zip_path"
    write_sha256 "$zip_path" "$zip_checksum_path"
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
    write_sha256 "$dmg_path" "$dmg_checksum_path"
fi

echo "$app_bundle"
