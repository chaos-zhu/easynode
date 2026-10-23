#!/bin/bash
set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_DIR="$(cd "$TOOLS_DIR/../.." && pwd)"
RDP_BUNDLE="$NATIVE_DIR/build/rdp/macos/bundle"
RDP_DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/rdp"
if [ ! -x "$RDP_BUNDLE/easynode-rdp" ]; then
  if [ "$CONFIGURATION" = Release ]; then
    echo 'error: Missing bundled RDP engine. Run tools/rdp/build-macos.sh first.' >&2
    exit 1
  fi
  echo 'warning: RDP engine not prepared. Run tools/rdp/build-macos.sh to enable local RDP.' >&2
  exit 0
fi
mkdir -p "$RDP_DEST"
rsync -a --delete "$RDP_BUNDLE/" "$RDP_DEST/"
RDP_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
RDP_IDENTITY="${RDP_IDENTITY:--}"
for library in "$RDP_DEST"/lib/*.dylib; do
  /usr/bin/codesign --force --sign "$RDP_IDENTITY" "$library"
done
if [ "$CONFIGURATION" = Release ]; then
  /usr/bin/codesign --force --options runtime --sign "$RDP_IDENTITY" --entitlements "$TOOLS_DIR/helper.entitlements" "$RDP_DEST/easynode-rdp"
else
  /usr/bin/codesign --force --sign "$RDP_IDENTITY" "$RDP_DEST/easynode-rdp"
fi
