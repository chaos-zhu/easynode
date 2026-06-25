# EasyNode HarmonyOS (OHOS) 构建说明

## 前置环境

| 工具 | 版本要求 | 说明 |
|------|----------|------|
| DevEco Studio | 5.0+ | HarmonyOS IDE、SDK 管理、签名配置 |
| HarmonyOS SDK | 5.0.0(12)+ | 编译目标 |
| Flutter-OH SDK | 3.41.10-ohos | 社区 fork（CPF-Flutter），命令行工具为 `flutter-oh` |
| Node.js | ≥ 18.15 | hvigor 构建系统依赖 |
| JDK | 17 | 构建工具链依赖 |

## dependency_overrides 说明

Flutter 标准插件不识别 OHOS 平台，需要通过 `dependency_overrides` 指向 CPF-Flutter 社区适配版本：

| 插件 | 来源 | 分支/版本 | 说明 |
|------|------|-----------|------|
| `shared_preferences` | `CPF-Flutter/flutter_packages` | 默认分支 | 键值存储 |
| `path_provider` | `CPF-Flutter/flutter_packages` | 默认分支 | 文件路径 |
| `url_launcher` | `CPF-Flutter/flutter_packages` | 默认分支 | 打开外部链接 |
| `flutter_secure_storage` | `CPF-Flutter/fluttertpc_flutter_secure_storage` | `br_v9.2.4_ohos` | 加密存储 |
| `flutter_secure_storage_ohos` | 同上 | `br_v9.2.4_ohos` | OHOS 平台实现 |
| `package_info_plus` | `CPF-Flutter/flutter_plus_plugins` | `br_package_info_plus-v8.1.0_ohos` | 包信息 |
| `share_plus` | `CPF-Flutter/flutter_plus_plugins` | `br_share_plus-v12.0.1_ohos` | 文件分享 |

额外依赖（非 override，直接添加到 dependencies）：

| 插件 | 来源 | 分支/版本 | 说明 |
|------|------|-----------|------|
| `file_picker_ohos` | `CPF-Flutter/fluttertpc_file_picker` | `br_v10.3.8_ohos` | 文件选择器，全平台替代包 |

## ohos_patch.sh 运行时补丁

部分 pub cache 中的包不识别 OHOS 平台，需要在 `pub get` 后运行 `ohos_patch.sh` 进行修补。**每次执行 `pub get` 后都需要重新运行。**

补丁内容：

| 目标包 | 修补内容 |
|--------|----------|
| `code_assets` os.dart | 添加 `OS.ohos` 枚举值到 OS 类和 values 列表 |
| `code_assets` syntax.g.dart | 添加 `OSSyntax.ohos` 枚举值到 OSSyntax 类和 values 列表 |
| `flutter_secure_storage` | 将 `throw UnsupportedError` 替换为 `return <String, String>{}` 兜底 |
| `xterm` shortcuts.dart | 在 switch 语句中添加 `default:` 分支避免 OHOS 平台抛异常 |

补丁覆盖两个 pub cache 目录：
- `~/.pub-cache/hosted/pub.dev/`
- `~/PUB/hosted/pub.flutter-io.cn/`（PUB_CACHE 环境变量指定）
- `~/PUB/git/`（git 依赖缓存）

## 构建步骤

### Debug 构建 & 运行

```bash
cd native

# 1. 获取依赖
flutter-oh pub get

# 2. 运行补丁（每次 pub get 后必须执行）
bash ohos_patch.sh

# 3. 连接设备后运行
flutter-oh run
```

### Release 构建（HAP）

```bash
cd native

flutter-oh pub get
bash ohos_patch.sh
flutter-oh build hap --release
```

构建产物位于 `ohos/entry/build/default/outputs/` 目录，后缀为 `.hap`。

### Release 构建（APP，用于上架应用市场）

上架华为应用市场（AppGallery）需要提交 `.app` 格式的包，而非 `.hap`。

**HAP vs APP 区别：**
- **HAP** (HarmonyOS Ability Package)：模块级包，每个 module 编译产出一个 `.hap`，可用于本地安装测试
- **APP** (Application Package)：应用级包，将一个或多个 HAP 打包在一起，**上架应用市场必须提交此格式**

构建方式：

```bash
flutter-oh build app --release
```

### 清理构建缓存

遇到编译异常时可尝试清理缓存后重新构建：

```bash
rm -rf .dart_tool/hooks_runner/
rm -rf build/
rm -rf ohos/entry/build/
flutter-oh pub get
bash ohos_patch.sh
flutter-oh run
```

## 签名配置

Debug 签名由 DevEco Studio 自动生成，配置在 `ohos/build-profile.json5` 中。

Release 签名需要华为开发者证书，请在 DevEco Studio 中配置：
- Project Structure → Signing Configs → 添加 Release 签名
- 或手动编辑 `ohos/build-profile.json5` 的 `signingConfigs`

## 注意事项

- Flutter-OH SDK 是社区维护的 fork（CPF-Flutter），非 Google 官方支持
- `build-profile.json5` 中的 debug 签名路径为本地路径，不应提交到仓库
- 当前 CI/CD 暂无 OHOS 构建流水线，需本地构建
