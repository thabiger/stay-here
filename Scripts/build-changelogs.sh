#!/usr/bin/env bash
set -euo pipefail

TAG_NAME="${1:-}"
DIST_DIR="dist"
CHANGELOG_SOURCE_DIR=".changelog"
OUTPUT_CHANGELOG="CHANGELOG.md"
RELEASE_NOTES_FILE="$DIST_DIR/release-notes.md"

if [[ -z "$TAG_NAME" ]]; then
    echo "Error: No tag name provided." >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

# 1. Extract Release Notes for the current tag
RELEASE_NOTES_SOURCE="$CHANGELOG_SOURCE_DIR/$TAG_NAME.md"
if [[ ! -f "$RELEASE_NOTES_SOURCE" ]]; then
    RELEASE_NOTES_SOURCE="$CHANGELOG_SOURCE_DIR/unreleased.md"
fi

if [[ -f "$RELEASE_NOTES_SOURCE" ]]; then
    echo "Extracting release notes from $RELEASE_NOTES_SOURCE"
    cp "$RELEASE_NOTES_SOURCE" "$RELEASE_NOTES_FILE"
else
    echo "Warning: No release notes source found for $TAG_NAME or unreleased.md" >&2
    echo "# Release $TAG_NAME" > "$RELEASE_NOTES_FILE"
fi

# 2. Reconstruct CHANGELOG.md
echo "Reconstructing $OUTPUT_CHANGELOG from $CHANGELOG_SOURCE_DIR/"
echo "# Changelog" > "$OUTPUT_CHANGELOG"
echo "" >> "$OUTPUT_CHANGELOG"

# First, add unreleased if it exists
if [[ -f "$CHANGELOG_SOURCE_DIR/unreleased.md" ]]; then
    cat "$CHANGELOG_SOURCE_DIR/unreleased.md" >> "$OUTPUT_CHANGELOG"
    echo "" >> "$OUTPUT_CHANGELOG"
fi

# Then, add all versioned files in descending order
find "$CHANGELOG_SOURCE_DIR" -name "v*.md" | sort -r | while read -r file; do
    cat "$file" >> "$OUTPUT_CHANGELOG"
    echo "" >> "$OUTPUT_CHANGELOG"
done

echo "Successfully built $OUTPUT_CHANGELOG and $RELEASE_NOTES_FILE"
