# 移动端 SFTP 文本文件编辑器 — 设计稿

- 状态：已与用户对齐（2026-05-23）
- 范围：仅 `mobile/`（Flutter）；后端无改动
- 设计参考：`mobile/design/mobile.pen` 节点 `sYMaF`（代码编辑页）
- 不在范围：Web 端、`/sftp-v2` socket、`flutter test` 跑测试（按 CLAUDE.md 默认只跑 analyze）

## 1. 目标

在移动端 SFTP 文件列表里，允许用户单击文本文件直接进入全屏编辑页：浏览（带语法高亮 + 行号 + 折叠）、编辑（undo/redo、按语言格式化）、保存回远端，并对大文件 / 二进制做拒绝保护。

## 2. 用户决策回顾

| 维度 | 选择 |
| --- | --- |
| 入口 | 单击文件直接进入编辑器 |
| 大文件保护 | ≤ 2 MB + 前 8 KB NUL 嗅探 |
| 「格式化」按钮 + 编码 | 保留格式化（JSON / YAML / XML），仅 UTF-8 |
| 页面承载 | `Navigator.push` 全屏路由 |

## 3. 库选型

**采用 `re_editor` + `re_highlight`**（Reqable 团队，MIT）：

- 不基于 `TextField`，独立绘制；移动端大文本性能好（Reqable iOS/Android 同款）
- 自带 undo/redo、行号 (`indicatorBuilder`)、折叠 (`DefaultCodeChunkAnalyzer` 识别 `{}` `[]`)、find/replace 控制逻辑、近百种 highlight mode
- 软键盘、iOS 浮动光标、ime 输入有专门处理

替代方案：

- `flutter_code_editor` (Akvelon)：基于 TextField + highlight，移动端大文件易掉帧，2025 之后更新放缓。不选。
- `code_text_field`：旧，功能少。
- `code_forge`：依赖 dart:io，依赖 LSP/AI，过重。

## 4. 文件落地

### 4.1 新增依赖（`mobile/pubspec.yaml`）

```yaml
re_editor: <pub.dev 当前稳定版>
re_highlight: <pub.dev 当前稳定版>
yaml: ^3.1.2
xml: ^6.5.0
```

`re_editor` 与 `re_highlight` 仍在 0.x，实施第一步先 `flutter pub add re_editor re_highlight yaml xml` 让 pub 决定 caret range，再把结果固化到 pubspec.yaml。

### 4.2 新增源文件

```
mobile/lib/features/shell/editor/
  text_editor_page.dart         # 全屏编辑页 widget
  text_editor_controller.dart   # ChangeNotifier：脏标记 / 保存 / 放弃
  editor_language.dart          # 文件名 → (语言 id, highlight Mode)
  editor_text_sniffer.dart      # NUL 嗅探 + UTF-8 解码兜底
  editor_formatters.dart        # JSON / YAML / XML formatter
```

### 4.3 修改的源文件

- `mobile/lib/features/shell/sftp_session_manager.dart`
  - 新增 `readTextFile(remotePath, {maxBytes=2*1024*1024})` → 返回 `({Uint8List bytes, bool malformedUtf8})`，内部先 `sftp.stat` 拿大小（超限抛 `SftpFileTooLargeException`），再 `_readRemoteFile`，前 8 KB 嗅探 NUL（命中抛 `SftpBinaryFileException`）。
  - 新增 `writeTextFile(remotePath, content)` → `_writeRemoteFile(remotePath, utf8.encode(content))`。
  - 新增两个异常类型（同文件内 `class SftpFileTooLargeException`、`class SftpBinaryFileException` extends `Exception`），便于 UI 层精确分支。

- `mobile/lib/features/shell/sftp_tab.dart`
  - `_SftpFileRow.onTap`：非选择态下，目录走 `manager.openPath`（已有行为），文件改为调用新增的 `_openInEditor(entry)`。
  - `_openInEditor`：调用 `manager.readTextFile`，捕获 size / binary / generic 三类异常，分别 toast。成功后 `Navigator.push(MaterialPageRoute(builder: (_) => TextEditorPage(...)))`。

- `mobile/lib/l10n/strings_en.dart` + `strings_zh.dart`：新增 editor.* key（见 §7）。

## 5. UI

### 5.1 结构（对齐 sYMaF）

```
TextEditorPage  (Scaffold)
├─ _EditorAppBar      返回 + 文件名 + 路径 + undo + redo
├─ _EditorMetaBar     语言徽章 + "UTF-8 · LF · 2.4 KB"
├─ Expanded
│  └─ CodeEditor      re_editor 主体，dark theme，行号 + 折叠
├─ _EditorStatusBar   Ln/Col + 语言·Spaces + 总行/当前行
└─ SafeArea bottom
   └─ _EditorActionBar  未保存指示 + 格式化 + 保存
```

### 5.2 配色

| 区域 | 颜色 |
| --- | --- |
| 编辑器背景 | `#0A0F14` |
| 行号 / 默认 | `#4B5563` |
| 当前行号 | `#9CA3AF` |
| 状态栏背景 | `#111827` |
| 状态栏 border-top | `#1F2937` |
| 状态栏字 | `#9CA3AF` |
| 其余（AppBar、Meta、Action、Dialog） | 复用 `_SftpPalette` |

高亮主题：`re_highlight` 的 `atom-one-dark`，静态 const 引用。

### 5.3 交互

- AppBar undo / redo 按钮：直接代理 `CodeLineEditingController.undo()` / `redo()`，并按 `controller.canUndo` / `canRedo` 控制可点态。
- 格式化按钮：按当前语言是否在 `editor_formatters.dart` 中支持（JSON / YAML / XML）来控制启用；点击 → 调用对应 formatter；失败 → 弹 toast。
- 保存按钮：仅 `isDirty` 时主色高亮可点；保存中显示 loading（按钮内 spinner）；成功 → toast `editor.saved`、`isDirty=false`；失败 → toast `editor.saveFailed`，保留 isDirty。
- 返回（AppBar 返回 / 系统返回 / 手势返回）：`PopScope` 拦截，`isDirty` 时弹 dialog（继续编辑 / 放弃 / 保存并退出），否则直接 pop。
- 不实现：查找替换 / 编码切换 / 主题切换 / 字体大小 / 缩略图 / 自动换行开关 / 多文件 tab。

## 6. 数据流

```
[SFTP 文件行点击]
    │
    ▼
manager.readTextFile(path)
    │   ├─ sftp.stat → 大小 > 2 MB ─► SftpFileTooLargeException
    │   ├─ _readRemoteFile
    │   ├─ 前 8 KB 含 NUL ──────────► SftpBinaryFileException
    │   └─ utf8.decode(allowMalformed:true) → malformedUtf8 标记
    ▼
Navigator.push → TextEditorPage(path, bytes, malformedUtf8)
    │
    ▼
TextEditorController:
  - originalText = decoded
  - CodeLineEditingController.fromText(originalText)
  - 监听 text → 计算 isDirty
    │
    ▼ 用户编辑 …
    ▼
saveFile():
  - manager.writeTextFile(path, controller.text) (utf8.encode)
  - 成功 → originalText = controller.text → isDirty=false → toast
  - 失败 → toast，保持 isDirty
```

## 7. i18n key

| key | zh | en |
| --- | --- | --- |
| `editor.tooLarge` | 文件超过 2 MB，请下载后再编辑 | File exceeds 2 MB. Download to edit. |
| `editor.binary` | 二进制文件不支持编辑 | Binary file is not editable. |
| `editor.readFailed` | 读取失败：{0} | Read failed: {0} |
| `editor.saveFailed` | 保存失败：{0} | Save failed: {0} |
| `editor.saved` | 已保存 | Saved |
| `editor.unsaved` | 未保存 | Unsaved |
| `editor.format` | 格式化 | Format |
| `editor.save` | 保存 | Save |
| `editor.discardTitle` | 放弃修改？ | Discard changes? |
| `editor.discardBody` | 当前修改未保存，确定离开？ | Unsaved edits will be lost. Leave? |
| `editor.discardKeepEditing` | 继续编辑 | Keep editing |
| `editor.discardLeave` | 放弃 | Discard |
| `editor.discardSaveAndLeave` | 保存并退出 | Save & leave |
| `editor.malformedUtf8` | 文件含非 UTF-8 字节，保存可能丢失部分字符 | File contains non-UTF-8 bytes; saving may lose some characters. |
| `editor.formatUnsupported` | 当前语言不支持格式化 | Format not supported for this language. |
| `editor.formatFailed` | 格式化失败：{0} | Format failed: {0} |
| `editor.statusEncoding` | UTF-8 · LF · {0} | UTF-8 · LF · {0} |
| `editor.statusPosition` | Ln {0}, Col {1} | Ln {0}, Col {1} |
| `editor.statusLineCount` | {0} / {1} | {0} / {1} |
| `editor.statusSpaces` | Spaces: {0} | Spaces: {0} |

## 8. 错误处理矩阵

| 场景 | 行为 |
| --- | --- |
| 文件 > 2 MB | toast `editor.tooLarge`，不进入页面 |
| 二进制文件（前 8 KB 含 NUL） | toast `editor.binary`，不进入页面 |
| 读取失败（权限 / 网络） | toast `editor.readFailed: <e>`，不进入页面 |
| 解码遇到无效字节 | `utf8.decode(allowMalformed:true)` 兜底进入；进入后 toast 一次 `editor.malformedUtf8` 警告 |
| 保存失败 | toast `editor.saveFailed: <e>`，保留 isDirty |
| 格式化失败 | toast `editor.formatFailed: <e>`（包含 JSON/YAML/XML parser 行列信息） |
| 当前语言不支持格式化 | toast `editor.formatUnsupported` |

## 9. 模块职责

### 9.1 `editor_text_sniffer.dart`

```dart
class TextSniffResult {
  final bool isBinary;
  final bool malformedUtf8;
  final String text; // utf8.decode(allowMalformed:true) 结果
}

TextSniffResult sniffAndDecode(Uint8List bytes);
```

- 取前 `min(8192, bytes.length)` 个字节，遇到 0x00 → `isBinary=true`，跳过解码。
- 非二进制 → `utf8.decode(bytes, allowMalformed:true)`；同时用 `utf8.decode(bytes)` 试探一次（不抛出捕获），失败则 `malformedUtf8=true`。

### 9.2 `editor_language.dart`

```dart
class EditorLanguage {
  final String id;           // 用于 UI 显示，如 'YAML', 'JSON'
  final Mode? highlightMode; // re_highlight Mode；plaintext 为 null
  final bool formatSupported;
  final int defaultIndent;   // 2
}

EditorLanguage detectFromFileName(String name);
```

- 复用 `web/src/components/text-editor/index.vue` 的 ext → lang 映射；缺省 plaintext。
- 仅 json/yaml/xml 的 `formatSupported = true`。

### 9.3 `editor_formatters.dart`

```dart
String formatJson(String src); // throws FormatException
String formatYaml(String src); // throws FormatException
String formatXml(String src);  // throws FormatException
```

- `formatJson`：`jsonDecode` → `JsonEncoder.withIndent('  ').convert(...)`。
- `formatYaml`：`loadYaml` → 自写递归 dumper（YamlMap / YamlList / scalar / null / bool / num / string，2 空格缩进，字符串按需带引号）。注释会丢失，UI 上用 toast 警告。
- `formatXml`：`XmlDocument.parse(src).toXmlString(pretty: true, indent: '  ')`。

### 9.4 `text_editor_controller.dart`

```dart
class TextEditorController extends ChangeNotifier {
  TextEditorController({
    required this.sessionManager, // SftpSessionManager
    required this.remotePath,
    required String originalText,
    required this.language,
    required this.totalBytes,
  });

  final CodeLineEditingController code; // re_editor controller
  String _originalText;
  bool _saving = false;

  bool get isDirty => code.text != _originalText;
  bool get saving => _saving;
  bool get canFormat => language.formatSupported;

  Future<void> save();              // writeTextFile + 更新 originalText
  Future<void> saveAndLeave(NavigatorState nav);
  void format();                    // 按 language 选 formatter；写回 code.text
  void dispose();                   // dispose code
}
```

- `code` 监听文本变化时 `notifyListeners()`，驱动 footer 未保存指示器。
- `save` 内置 `_saving` 互斥，防止双击。

### 9.5 `text_editor_page.dart`

- `StatefulWidget`，`initState` 创建 `TextEditorController`，`dispose` 释放。
- 用 `PopScope(canPop: !isDirty, onPopInvoked: ...)` 拦截返回。

## 10. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| Android 第三方 IME（搜狗 / 百度）联想抖动 | `re_editor` 已处理大多数 IME；遇到 QA 反馈可临时打开 wordWrap 减少水平滚动冲突 |
| 用户误点击大文件等待几秒才被拒 | 先 `sftp.stat` 拿大小，未读取数据就拦截；NUL 嗅探在内存里很快 |
| YAML 格式化丢注释 | toast 警告；本期不引入 `yaml_writer` / 自研 round-trip |
| 保存中网络中断 | toast 报错，保留 isDirty，用户可手动重试 |
| 文件不是 UTF-8（如 GB18030） | `allowMalformed:true` 不让进入页面崩溃；toast 告知用户保存可能损坏 |

## 11. YAGNI 列表（本期不做）

- 查找 / 替换 UI（re_editor 已有逻辑，UI 待后续 PR）
- 编码切换、行尾切换、主题切换、字体大小、缩略图、word wrap toggle
- 多文件 tab、最近编辑历史、本地草稿恢复
- 长按菜单的「编辑」入口（如有需求再加，到时和单击同走 `_openInEditor`）
- 后端 socket 协作编辑

## 12. 测试

按 CLAUDE.md，默认只跑 `flutter analyze` + format；下列单测仅在用户明确要求时执行：

- `mobile/test/features/shell/editor/editor_text_sniffer_test.dart`
- `mobile/test/features/shell/editor/editor_language_test.dart`
- `mobile/test/features/shell/editor/editor_formatters_test.dart`
- `mobile/test/features/shell/editor/text_editor_controller_test.dart`（用 fake `SftpSessionManager`）

## 13. 实施步骤索引（实际拆分见 plan）

1. 加依赖 + 创建 `editor/` 目录骨架。
2. `editor_text_sniffer.dart` + `editor_language.dart` + 单测。
3. `editor_formatters.dart` + 单测。
4. `SftpSessionManager` 新增 `readTextFile` / `writeTextFile` + 异常类。
5. `TextEditorController` + 单测。
6. `TextEditorPage` UI 拼装（AppBar / Meta / Editor / StatusBar / ActionBar）。
7. i18n 补 key。
8. `sftp_tab.dart` 接入单击入口，三类异常 toast。
9. `flutter analyze` + 手动 / 模拟器自查。
