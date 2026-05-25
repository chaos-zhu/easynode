# EasyNode Mobile

EasyNode 的 Flutter 移动端 App，复用现有后端 (`/api/v1`)，在手机上提供服务器列表、SSH 终端、SFTP 文件管理、脚本库、账户安全等能力。App 自身不打包后端地址，登录时由用户填写。

## 技术栈

- Flutter `^3.11.5`
- Riverpod (`flutter_riverpod`) 状态管理
- Dio + dio_cookie_manager + flutter_secure_storage 网络与持久化
- dartssh2 + xterm 终端
- pointycastle + basic_utils RSA / AES-GCM 加密
- re_editor / photo_view / video_player + chewie 文件预览与编辑

## 目录结构

```
mobile/
├── lib/
│   ├── main.dart                   # 入口，调用 EasyNodeApp.bootstrap()
│   ├── app.dart                    # 启动装配、ProviderScope override、登录态路由
│   ├── core/
│   │   ├── api/                    # ApiClient / Cookie / 通用错误
│   │   ├── crypto/                 # RSA、AES-GCM、CryptoJS 兼容
│   │   ├── storage/                # SharedPreferences + SecureStorage + deviceId
│   │   ├── i18n/                   # 多语言资源
│   │   ├── ui/                     # 主题色板
│   │   └── utils/                  # JWT、表单校验
│   ├── features/
│   │   ├── auth/                   # 登录页、登录控制器、AuthSession
│   │   ├── servers/                # 服务器列表、表单、Repository、模型
│   │   ├── terminal/               # SSH 通道、xterm 控制器、会话管理、工具栏
│   │   ├── scripts/                # 脚本库与脚本分组
│   │   ├── settings/               # 账户安全、凭据、代理、登录日志、Plus
│   │   └── shell/                  # MainShell / SFTP / 编辑器 / 媒体预览
│   ├── state/                      # Riverpod providers (auth、host list、terminal …)
│   └── l10n/                       # 多语言入口
├── android/                        # Android 工程，含 key.properties.example
├── ios/                            # iOS 工程
├── assets/                         # 图标 / 图片资源
└── test/                           # 单元测试，按 lib 目录镜像组织
```

## 架构概览

### 启动链路

1. `main.dart` 调用 `EasyNodeApp.bootstrap()`。
2. `bootstrap()` 内同步初始化 `AppStorage` / `SecureAppStorage` / `SessionCookieStore`，读取已保存的 token、session cookie、deviceId。
3. 若三者齐全则尝试预拉服务端公钥并构造 `AuthState`，失败时清理本地登录态。
4. 通过 `ProviderScope.overrides` 把上述存储与 `AuthNotifier` 注入根作用域。
5. `_AppRoot` 监听 `authProvider.signedIn`，在 `LoginPage` 与 `MainShellPage` 之间切换。

> 所有存储 provider 在 `state/storage_providers.dart` 里默认 `throw UnimplementedError(...)`，必须由 bootstrap 阶段 override；任何其它代码路径不要直接 new。

### 状态管理 (Riverpod)

- `state/auth_notifier.dart`：`signIn()` 写本地存储并切到登录态；`signOut()` 关闭所有终端会话、清 token / cookie / deviceId。
- `state/auth_state.dart`：登录后唯一持有的 `ApiClient` + 服务端公钥 PEM。
- `state/host_list_notifier.dart`、`terminal_providers.dart`、`api_providers.dart`：主机列表、终端会话、各 Repository 的装配。

### 网络层

- `core/api/api_client.dart`：`baseUrl = $serverAddress/api/v1`，Dio 拦截器注入 `token` header 和 `Cookie`；响应里 `set-cookie` 自动回写 `SessionCookieStore`；401/403 抛 `UnauthorizedFailure`。
- `core/api/cookie_store.dart`：基于 `flutter_secure_storage` 持久化 cookie，启动时回放给 Dio。
- 所有 feature 都通过 `authProvider` 暴露的 `ApiClient` 调用接口，不要再 new。

### 加密协议

- 登录密码：`core/crypto/rsa_crypto.dart#encryptPassword` → PKCS1 + utf8，对应服务端 `node-rsa.decrypt(ct, 'utf8')`。
- 移动端 SSH 临时密钥：32 字节 AES key → base64 → utf8 → RSA，对应 `RSADecryptAsync` + `Buffer.from(text, 'base64')`。
- `/mobile/ssh-connection` 返回的 `{ iv, tag, ciphertext }` 由 `core/crypto/aes_gcm_crypto.dart` AES-GCM 解密。
- **修改加密协议必须 server / mobile 同步升级**，否则破坏现有 App 兼容性。

### 登录流程

1. 校验并规范化服务器地址（去尾斜杠，HTTP 需要二次确认）。
2. `GET /get-pub-pem` 获取 RSA 公钥。
3. RSA 加密密码，`POST /login` 拿 token + session cookie。
4. 回调 `_onLoginSuccess`，由 `AuthNotifier.signIn` 持久化并触发跳转。

### 主壳

`features/shell/main_shell_page.dart` 是四个 tab 的 IndexedStack 保活容器：

- `ServersTab`：服务器列表，点击连接走 `ApiServerRepository.fetchSshConfig(hostId)` → `TerminalSessionManager.openSession()` 在本地起 dartssh2 session。
- `SftpTab`：SFTP 文件操作。
- `ScriptsTab`：脚本库与脚本分组。
- `SettingsTab`：账户安全 / 凭据 / 代理 / 登录日志 / Plus。

登出由 `authProvider` 状态变更触发 `_AppRoot` 回到 `LoginPage`，不需要手动 pop。

### 终端 / SSH

- `features/terminal/ssh_terminal_controller.dart`：dartssh2 起 shell session，stdout/stderr 写入 `xterm.Terminal`；`terminal.onOutput` 把按键回送给 SSH session；支持 `Ctrl + 字母` 一次性修饰键。Shell 启动后主动 `resizeTerminal()` 一次，避免 PTY 卡在 80x24。
- `terminal_session_manager.dart`：所有终端会话集合 + 当前激活 id，提供 open / setActive / reconnect / close / closeAll。`reconnect` 复用现有 `Terminal` buffer，避免清屏。
- `ssh_connection_config.dart`：与服务端 `toMobileSshPayload` 对齐的纯数据类。
- `http_proxy_connector.dart` / `socks5_connector.dart` / `ssh_transport.dart`：代理与跳板机连接通道。

### 存储分层

- `AppStorage`（SharedPreferences）：普通偏好，例如 server address、username、save password 开关。
- `SecureAppStorage`（flutter_secure_storage）：token、session cookie、密码、deviceId。
- `device_id.dart`：deviceId 生成与缓存。

## 本地开发

所有命令在 `mobile/` 目录下执行。

```bash
flutter pub get          # 拉依赖
flutter run              # 连接设备 / 模拟器调试
flutter analyze          # 静态分析，对齐 package:flutter_lints/flutter.yaml
flutter test             # 单元测试（仅在显式需要时执行）
```

协作约束：默认只跑格式化和 `flutter analyze`，不跑 `flutter test`；只有明确要求时才运行测试。控制器 / repository 通过构造参数注入依赖，测试里走 fake，不要打真实网络。

## 打包步骤

### Android

1. **准备签名密钥**（仅首次）

   ```bash
   keytool -genkeypair -v -keystore easynode-release.jks \
     -alias easynode -keyalg RSA -keysize 2048 -validity 10000
   ```

   把生成的 `easynode-release.jks` 放到 `mobile/android/` 下。

2. **创建 `mobile/android/key.properties`**

   参考 `key.properties.example`：

   ```properties
   storePassword=<your-store-password>
   keyPassword=<your-key-password>
   keyAlias=easynode
   storeFile=easynode-release.jks
   ```

   该文件已被 `.gitignore` 忽略，**不要提交**。如果不提供，`build.gradle.kts` 会回退到 debug keystore，仅供本地 `flutter run --release` 使用，正式产物必须有 release keystore。

3. **更新版本号**

   编辑 `mobile/pubspec.yaml` 顶部的 `version: x.y.z+build`，`+` 之前是 `versionName`，之后是 `versionCode`。

4. **构建产物**

   ```bash
   flutter pub get
   flutter clean                              # 可选，更新插件后建议执行
   flutter build apk --release                # 通用 APK
   flutter build apk --release --split-per-abi  # 按 ABI 拆分（推荐用于分发）
   flutter build appbundle --release          # Google Play 上架用 AAB
   ```

   产物位置：

   - APK: `mobile/build/app/outputs/flutter-apk/`
   - AAB: `mobile/build/app/outputs/bundle/release/`

### iOS

iOS 构建需要 macOS + Xcode。

1. **首次准备**

   ```bash
   cd mobile/ios
   pod install
   ```

2. **在 Xcode 配置签名**

   用 Xcode 打开 `mobile/ios/Runner.xcworkspace`，在 `Runner` → `Signing & Capabilities` 配置 Team / Bundle Identifier / Provisioning Profile。

3. **构建归档**

   ```bash
   flutter build ipa --release
   ```

   或在 Xcode 中选择 `Product → Archive`，再通过 Organizer 上传到 App Store Connect / 导出 Ad-hoc IPA。

   产物位置：`mobile/build/ios/archive/` 与 `mobile/build/ios/ipa/`。

### 发布前自检

- `flutter analyze` 通过。
- 在真机 release 模式运行一次（`flutter run --release`）。
- 确认登录页能输入服务器地址、HTTP 地址有风险提示、HTTPS 不提示。
- 确认终端、SFTP、脚本三个 tab 能正常访问后端。
- 确认登出后 token / cookie / deviceId 已清空。

## 后端约定

- 移动端复用 `/api/v1` 全部接口，鉴权与 Web 端一致：`token` header + `session` cookie。
- 专属端点：`POST /api/v1/mobile/ssh-connection`，返回 AES-GCM 加密后的 SSH 连接参数。修改时同步更新 `server/app/controller/mobile.js` 与 `mobile/lib/features/servers/server_repository.dart`、`mobile/lib/core/crypto/aes_gcm_crypto.dart`。
- 解密后的 SSH 凭据**不得写入磁盘或日志**。
