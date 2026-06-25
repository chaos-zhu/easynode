#!/bin/bash
# Flutter OHOS 构建 Patch
# 为 code_assets 和 xterm 包添加 ohos 平台支持
# 重新执行 pub get 后可能需要再次运行

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
count=0

# 清除 hooks_runner 编译缓存，确保 patch 生效
if [ -d "$SCRIPT_DIR/.dart_tool/hooks_runner" ]; then
  rm -rf "$SCRIPT_DIR/.dart_tool/hooks_runner"
  echo "cleared: .dart_tool/hooks_runner cache"
fi

# patch code_assets os.dart
for f in ~/.pub-cache/hosted/*/code_assets-*/lib/src/code_assets/os.dart ~/PUB/hosted/*/code_assets-*/lib/src/code_assets/os.dart; do
  [ -f "$f" ] || continue
  grep -q "ohos" "$f" && continue
  sed -i '' "s/static const OS windows = OS._('windows');/static const OS windows = OS._('windows');\n\n  static const OS ohos = OS._('ohos');/" "$f"
  sed -i '' "s/static const List<OS> values = \[android, fuchsia, iOS, linux, macOS, windows\];/static const List<OS> values = [android, fuchsia, iOS, linux, macOS, windows, ohos];/" "$f"
  echo "patched: $f"
  ((count++))
done

# patch code_assets syntax.g.dart
for f in ~/.pub-cache/hosted/*/code_assets-*/lib/src/code_assets/syntax.g.dart ~/PUB/hosted/*/code_assets-*/lib/src/code_assets/syntax.g.dart; do
  [ -f "$f" ] || continue
  grep -q "ohos" "$f" && continue
  sed -i '' "s/static const windows = OSSyntax._('windows');/static const windows = OSSyntax._('windows');\n\n  static const ohos = OSSyntax._('ohos');/" "$f"
  sed -i '' "s/static const List<OSSyntax> values = \[android, iOS, linux, macOS, windows\];/static const List<OSSyntax> values = [android, iOS, linux, macOS, windows, ohos];/" "$f"
  echo "patched: $f"
  ((count++))
done

# patch flutter_secure_storage: _selectOptions 添加 OHOS fallback
for f in ~/.pub-cache/git/fluttertpc_flutter_secure_storage-*/flutter_secure_storage/lib/flutter_secure_storage.dart ~/PUB/git/fluttertpc_flutter_secure_storage-*/flutter_secure_storage/lib/flutter_secure_storage.dart; do
  [ -f "$f" ] || continue
  grep -q "return <String, String>{};" "$f" && continue
  sed -i '' "s/throw UnsupportedError(UNSUPPORTED_PLATFORM);/return <String, String>{};/" "$f"
  echo "patched: $f"
  ((count++))
done

# patch xterm shortcuts.dart
for f in ~/.pub-cache/hosted/*/xterm-*/lib/src/ui/shortcut/shortcuts.dart ~/PUB/hosted/*/xterm-*/lib/src/ui/shortcut/shortcuts.dart; do
  [ -f "$f" ] || continue
  grep -q "default:" "$f" && continue
  sed -i '' 's/case TargetPlatform.macOS:/case TargetPlatform.macOS:\n    default:/' "$f"
  echo "patched: $f"
  ((count++))
done

if [ $count -eq 0 ]; then
  echo "all files already patched."
else
  echo "done. patched $count file(s)."
fi
