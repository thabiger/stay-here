#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Build a distributable macOS .app bundle from the SwiftPM target.

Usage:
  Scripts/build-release-app.sh [options]

Options:
  --app-name NAME           App bundle name. Default: StayHere
  --target-name NAME        SwiftPM executable target name. Default: StayHereApp
  --bundle-id ID            Bundle identifier. Default: com.tha.stayhere
  --version VERSION         CFBundleShortVersionString. Default: 0.1.0
  --build-number NUMBER     CFBundleVersion. Default: git short SHA or 1
  --output-dir DIR          Directory that will contain the .app bundle. Default: dist
  --identity ID             Codesign identity. If omitted, the bundle is ad hoc signed.
  --no-sign                 Skip codesigning entirely.
  --entitlements FILE       Entitlements plist to pass to codesign when signing.
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
CLEAN_OUTPUT=1
SIGN_MODE="adhoc"

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

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(git rev-parse --short HEAD 2>/dev/null || echo 1)"
fi

if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    rm -rf "$OUTPUT_DIR/$APP_NAME.app"
fi
mkdir -p "$OUTPUT_DIR"

echo "Building release binary for $TARGET_NAME"
swift build -c release --product "$TARGET_NAME"

bin_path="$(swift build -c release --show-bin-path)"
binary="$bin_path/$TARGET_NAME"

if [[ ! -x "$binary" ]]; then
    echo "Expected release binary not found: $binary" >&2
    exit 1
fi

app_bundle="$OUTPUT_DIR/$APP_NAME.app"
contents="$app_bundle/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"

mkdir -p "$macos_dir" "$resources_dir"
cp "$binary" "$macos_dir/$APP_NAME"
chmod +x "$macos_dir/$APP_NAME"

cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    SIGN_MODE="identity"
fi

if [[ "$SIGN_MODE" != "none" ]]; then
    codesign_args=(
        --force
        --options runtime
    )
    if [[ "$SIGN_MODE" == "identity" ]]; then
        codesign_args+=(--sign "$CODESIGN_IDENTITY" --timestamp)
    else
        codesign_args+=(--sign -)
    fi
    if [[ -n "$ENTITLEMENTS_PATH" ]]; then
        codesign_args+=(--entitlements "$ENTITLEMENTS_PATH")
    fi
    codesign "${codesign_args[@]}" "$app_bundle"
    codesign --verify --deep --strict --verbose=2 "$app_bundle"
else
    echo "No codesign identity provided; leaving $app_bundle unsigned."
fi

echo "$app_bundle"
