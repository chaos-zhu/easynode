# Windows / macOS 本地开发

桌面端与移动端共用 `native` 工程、Material 3、Riverpod 和登录协议。
通过操作系统选择桌面页面，不根据窗口宽度切换到移动端。业务页面暂时占位，
不会加载主机目录、建立 SSH/SFTP 连接、启动 AI 浮窗或检查更新。

## 运行

在 `native/` 下执行：

```sh
flutter pub get
flutter run -d macos
```

Windows 必须在 Windows 主机上安装 Flutter 和 Visual Studio 的
“使用 C++ 的桌面开发”工具链，再执行：

```powershell
flutter pub get
flutter run -d windows
flutter build windows --debug
```

窗口默认 1280 × 800，最小内容尺寸 900 × 640，保留系统标题栏。
Windows 的最小尺寸按当前屏幕 DPI 换算，并计入系统窗口边框。

## Apple 依赖与签名

- 当前 HarmonyOS `package_info_plus` 分支的 macOS `Package.swift` 缺少逗号，
  因此项目暂时关闭 Swift Package Manager，使用现有 iOS/macOS Podfile。
  上游修复后再重新验证和开启；不修改全局 Flutter 配置或本机依赖缓存。
- macOS Debug/Profile 使用非沙箱本地构建和系统加密登录 Keychain，
  无需先配置 Apple 开发证书。此配置仅用于开发。
- Release 保留 App Sandbox、网络客户端权限和 Keychain 权限，使用数据保护
  Keychain；正式分发前需要配置开发团队、稳定 Bundle ID 和签名。
  Debug/Profile 与 Release 的 Keychain 后端不同，本阶段不迁移开发会话。
- 所有模式都通过 `flutter_secure_storage` 存储秘密；存储失败时提示重试，
  不降级到 SharedPreferences 或明文文件。

## 登录与状态边界

- 登录复用服务端地址、RSA 密码加密、可选 MFA 和 3/7/30 天有效期。
  HTTP 必须确认风险，自签名 HTTPS 证书必须确认 SHA-256 指纹；指纹变化重新确认。
- 每次登录使用独立内存 cookie，失败后丢弃。成功后才把 cookie、deviceId、token
  写入系统安全存储，token 最后写入，作为会话提交标志。
- 只支持一个活跃账号。保存密码按服务地址和用户名区分；历史账号仅保存元信息。
- 退出时关闭旧 API 客户端并清理会话，新的登录提交等待旧清理完成。
  桌面主动退出若清理失败则留在原界面提示重试；保存的密码和历史账号保留，
  可在登录历史中删除。
- 冷启动用轻量鉴权接口确认会话。临时断网保留凭据并允许重连，鉴权失效回到登录。
- 桌面壳只持有导航状态，不挂载移动端业务壳及其数据初始化 provider。
- 侧栏顶部直接展示菜单，不展示品牌标题或折叠按钮。底部参照 Web 展示用户名和
  Plus 入口；点击用户名打开版本、主题、AI 助手、折叠和退出菜单，退出无需二次确认。
  版本入口仅展示当前版本及项目链接，AI 助手暂不可用，Plus 入口进入系统设置占位页。
- 侧栏展开宽度 174，折叠宽度 64。桌面弹窗统一使用
  `lib/core/ui/app_dialog.dart` 的 `showAppDialog<T>`，保留 `builder` 和返回值用法。
  入场为 260ms 淡入与 20px 位移，退场为 180ms；尊重系统减少动画设置。
  HTTP、证书、登录历史、删除确认、版本及 IP 限制弹窗已接入，移动端仍使用标准弹窗。
  `closeOnPressEscape` 默认 `true`，独立控制 Esc 关闭，与遮罩点击关闭
  `barrierDismissible` 分开设置；证书和 IP 限制弹窗显式设为 `false`。

## 后续接入真实业务前

必须为终端、SFTP、状态监控和每级跳板机统一接入 SSH 主机指纹校验。
当前 `dartssh2` 调用未配置 `onVerifyHostKey`，不能把 HTTPS 证书确认当作 SSH
主机身份校验。参考 Netcatty 的首次确认、已知主机匹配和指纹变化阻断流程。

逐项迁移 Web 功能时继续按业务域拆分 Riverpod 状态和 Repository。
业务数据以服务端为来源，本地偏好与系统安全存储分离；暂不新增本地数据库。
RDP、批量指令和定时任务需单独设计执行路径。

## 检查

默认运行 `flutter analyze`，不默认运行 `flutter test`。
分别在两端检查登录/MFA失败、重复提交、HTTP/证书确认、账号选择/删除、
保存/取消保存密码、冷启动恢复、断网重试和退出清理。
检查九个菜单、折叠侧栏、主题、系统缩放和中英文；窗口变小时应滚动且保持桌面布局。
macOS 构建成功不代表 Windows 已通过构建或系统安全存储验证。

2026-10-19：macOS debug 构建、`flutter analyze` 和真实应用窗口验证已通过。
交互验证使用独立的 SharedPreferences 前缀、独立 Keychain 服务及本机 HTTP/HTTPS
测试服务，覆盖错误密码/MFA、HTTP 取消/确认、旧 cookie 隔离、保存/不保存密码、
历史账号选择/删除、冷启动恢复、会话失效、断网重连、退出清理、自签证书确认、
证书变化后取消，以及全部菜单、侧栏折叠、主题和中英文渲染。
验证了最小窗口下的实际渲染；Windows 构建、安全存储及系统缩放仍需 Windows 主机实测。
未运行 `flutter test`，未构建 Release 或安装包。
