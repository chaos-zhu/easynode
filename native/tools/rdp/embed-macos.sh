#!/bin/bash
set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_DIR="$(cd "$TOOLS_DIR/../.." && pwd)"
RDP_BUNDLE="$NATIVE_DIR/build/rdp/macos/bundle"
RDP_DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/rdp"
RDP_RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/rdp"
if [ ! -x "$RDP_BUNDLE/easynode-rdp" ]; then
  if [ "$CONFIGURATION" = Release ]; then
    echo 'error: Missing bundled RDP engine. Run tools/rdp/build-macos.sh first.' >&2
    exit 1
  fi
  echo 'warning: RDP engine not prepared. Run tools/rdp/build-macos.sh to enable local RDP.' >&2
  exit 0
fi
mkdir -p "$RDP_DEST"
rsync -a --delete --delete-excluded --exclude=licenses --exclude=engine-version.txt "$RDP_BUNDLE/" "$RDP_DEST/"
# Helpers is a nested-code directory. Plain-text licenses belong in Resources,
# otherwise codesign attempts to validate them as executable subcomponents.
mkdir -p "$RDP_RESOURCES/licenses"
rsync -a --delete "$RDP_BUNDLE/licenses/" "$RDP_RESOURCES/licenses/"
cp "$RDP_BUNDLE/engine-version.txt" "$RDP_RESOURCES/engine-version.txt"
RDP_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
RDP_IDENTITY="${RDP_IDENTITY:--}"
SIGN_OPTIONS=(--timestamp=none)
if [[ "${EXPANDED_CODE_SIGN_IDENTITY_NAME:-}" == "Developer ID Application:"* ]]; then
  SIGN_OPTIONS=(--timestamp)
fi
for library in "$RDP_DEST"/lib/*.dylib; do
  /usr/bin/codesign --force --sign "$RDP_IDENTITY" "${SIGN_OPTIONS[@]}" "$library"
done
if [ "$CONFIGURATION" = Release ]; then
  /usr/bin/codesign --force --options runtime --sign "$RDP_IDENTITY" "${SIGN_OPTIONS[@]}" --entitlements "$TOOLS_DIR/helper.entitlements" "$RDP_DEST/easynode-rdp"
else
  /usr/bin/codesign --force --sign "$RDP_IDENTITY" "$RDP_DEST/easynode-rdp"
fi
