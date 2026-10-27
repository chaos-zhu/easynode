#!/bin/bash
set -euo pipefail
TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_DIR="$(cd "$TOOLS_DIR/../.." && pwd)"
RDP_BUILD="$NATIVE_DIR/build/rdp/macos"
for tool in cmake ninja python3 brew; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install: brew install cmake ninja python sdl3 sdl3_ttf openssl@3 cjson" >&2; exit 1; }
done
BREW_PREFIX="$(brew --prefix)"
# A host beta can be newer than the SDK; use the SDK as the development default.
RDP_MACOS_TARGET="${EASYNODE_RDP_MACOS_TARGET:-$(xcrun --sdk macosx --show-sdk-version)}"
RDP_SOURCE="$(python3 "$TOOLS_DIR/prepare.py" "$NATIVE_DIR/build/rdp/source")"
cmake -S "$RDP_SOURCE" -B "$RDP_BUILD/cmake" -G Ninja -C "$TOOLS_DIR/engine-options.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$BREW_PREFIX;$BREW_PREFIX/opt/openssl@3" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$RDP_MACOS_TARGET" -DCMAKE_INSTALL_PREFIX="$RDP_BUILD/install"
cmake --build "$RDP_BUILD/cmake" --target sdl3-freerdp --parallel
python3 "$TOOLS_DIR/bundle-macos.py" "$RDP_BUILD/cmake" "$RDP_BUILD/bundle" "$RDP_SOURCE"
echo "RDP engine prepared. Rebuild EasyNode to embed it."
