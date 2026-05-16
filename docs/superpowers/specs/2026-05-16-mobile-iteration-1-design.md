# EasyNode Mobile Iteration 1 Design

Date: 2026-05-16

## Goal

在 `2026-05-16-mobile-native-terminal-design.md` 的初版基础上完善登录页、服务器列表页、终端页的体验与稳定性，重点处理两个已知 bug，引入应用级终端会话管理以支撑后续多终端 / 挂起 / 批量命令等扩展。

## Scope

包含：

- 修复"保存密码"开关无法回填密码的 bug
- 修复登录态无法持久化（下次进入仍走登录页）
- 应用级 `TerminalSessionManager`，会话所有权与页面解耦
- 终端页重构为带顶部 Toolbar、底部 shortcut bar 的 shell 页面
- 服务器列表页 UI/体验优化
- 登录页 UI/体验优化
- 跨页 401/403 自动跳回登录、暗色主题

不包含：

- 服务器 CRUD、SFTP、RDP、跳板机
- SH 会话挂起到磁盘（manager 内存级生命周期已为后续挂起预留接口）
- 字号 / 主题持久化（终端字号本轮固定）

## Bug 根因与修复

### 保存密码不回填

`EasyNodeApp._hydrateInitialPassword()` 在 `initState` 之后异步读密码并 `setState`，但 `LoginPage._LoginPageState._pwdCtrl` 只在子 State 的 `initState` 里读了一次 `widget.initialPassword`。父 State 后来把新值传下来时，`TextEditingController` 不会自动更新。

修复：将密码加载提前到启动期，与其它持久化字段一起在 `EasyNodeApp.bootstrap()` 中读完，第一帧 `LoginPage` 即拿到 `initialPassword`。

### 登录态不持久

`app.dart` 没有任何启动时恢复 session 的逻辑。即使 token / sessionCookie / deviceId 已写入安全存储，每次进入仍创建空 `_session`，回到登录页。

修复：bootstrap 中尝试恢复 session：

1. 读 serverAddress、username、token、sessionCookie、deviceId、savePassword、password
2. 如果 token 与 sessionCookie 齐全，构建 `ApiClient` 并调用 `/get-pub-pem`
   - 成功：构造 `AuthSession`，跳过登录直接进入服务器列表
   - 401/403/网络失败：清 token + sessionCookie + deviceId，回登录页（保留 serverAddress / username / savePassword / password 偏好）
3. 启动期间显示轻量 splash（指示器 + 应用名），避免空白闪屏

## 应用级终端会话管理

### `TerminalSessionManager`

- `extends ChangeNotifier`，根级注入，所有 widget 通过 `InheritedNotifier` / `Provider` 风格 `_TerminalSessionScope` 访问
- 持有 `List<TerminalSession>`：
  - `id` (uuid v4)
  - `hostId`
  - `displayName`
  - `status`: `connecting` | `connected` | `disconnected` | `error`
  - `lastError`
  - `controller`: `SshTerminalController`
- 公开方法：
  - `Future<TerminalSession> openSession(SshConnectionConfig)`
  - `Future<void> closeSession(String id)`
  - `void setActive(String id)`
  - `String? get activeId`
  - `Iterable<TerminalSession> get sessions`
  - `Future<void> reconnect(String id)`
- session 生命周期与页面 routes 完全解耦；manager 是唯一所有者
- session 状态变更通过 `notifyListeners` 推送 UI；同时把 `[Disconnected]` / `[Reconnecting]` 写入对应 xterm Terminal，保留 scrollback

### 侧滑返回不断开

- 路由 pop 不调 `disconnect()`；manager 持有 controllers
- 重新 push 终端页时通过 manager 拿现有 session，xterm Terminal 实例复用，scrollback 完整保留

## 终端页 (`TerminalShellPage`)

页面结构：

```
┌─────────────────────────────────┐
│ [⚏³]      api-1  ●已连接       [＋]  [✕]   │  Toolbar (高 52)
├─────────────────────────────────┤
│                                                │
│           xterm view (active session)          │
│                                                │
├─────────────────────────────────┤
│  Esc  Tab  Ctrl-C  ↵  ↑↓←→  Ctrl-D ...  →   │  Shortcut bar (高 44)
└─────────────────────────────────┘
```

### Toolbar

固定高度 52，水平排布。

**左：紫色堆叠图标 (`StackedSessionsIcon`)**

- `CustomPaint` 绘制三层错位矩形，从深紫到浅紫渐变，2px 错位投影
- 右上角徽标显示当前 session 数；只有 1 个时图标变单层、无徽标
- 点击通过 `OverlayEntry` 在图标左下角弹出菜单：
  - 宽度 240
  - 高度 `min(行数 × 48 + 16, screenHeight × 0.55)`
  - 超出最大高度时启用 `Scrollbar` 常显的纵向滚动
  - 行结构：状态点 + session 名（超长省略），当前项右侧 ✓ 且浅紫高亮背景
  - 点击行 → `setActive(id)` 后关闭浮层
  - 点外部 / 返回键关闭

**中：当前 session 名 + 状态徽章**

- session 名超长省略
- 状态徽章：圆点 + 文字（连接中黄、已连接绿、已断开灰、错误红）

**右：`＋` 新建、`✕` 关闭**

`＋` 点击弹出"打开服务器"菜单（同样基于 OverlayEntry）：

- 宽度 280
- 高度 `min(内容高, screenHeight × 0.55)`，超出滚动
- 行结构：服务器名 + `username@host:port`；已连接的 host 右侧加绿色小点提示再点会再开一个 session
- 点击行 → 取 SSH 参数 → `manager.openSession()` → 自动 `setActive` 到新 session

`✕` 点击关闭当前 session：

- 已连接状态弹小气泡 confirm；已断开直接关
- 关闭后查剩余：
  - 还有 → `setActive(剩余 list.first.id)` 留在终端页
  - 没有 → `Navigator.pop` 回服务器列表

### 终端区

- `IndexedStack` 承载所有 session 的 `TerminalView`，切换不重建
- 黑底浅灰前景（强制暗色，独立于 app 主题）
- `MediaQuery.viewInsets.bottom` 决定底部留白；`onResize` 推到 `SSHSession.resizeTerminal`

### Shortcut bar

- `resizeToAvoidBottomInset: true`，键盘弹起时整条上移到键盘上沿
- 横向滚动 `ListView.scrollDirection: Axis.horizontal`，不换行
- 按频率排序（首版顺序，后续可调）：
  ```
  Esc  Tab  Ctrl-C  ↵  ↑  ↓  ←  →  Ctrl-D  Ctrl-Z  |  ~  /  -  Ctrl-L  Ctrl-A  Ctrl-E  PgUp  PgDn
  ```
- 每键 minWidth 48，左右各 4 padding
- Ctrl 粘性键：按一下进入"Ctrl 待发"高亮态，下一个字母键发送 `Ctrl-X` 后自动复位；再按 Ctrl 取消

### 断线策略

- 断线 tab 不自动关闭，状态点灰，xterm 写入 `\r\n[Disconnected]\r\n`
- Toolbar `⚏` 菜单中断线项支持点击触发 reconnect；`SshTerminalController` 复用同一 xterm Terminal，保留 scrollback
- 第一版不主动发 SSH keep-alive

## 服务器列表页

### 顶部活跃终端 banner

`manager.sessions.isNotEmpty` 时显示：紫色堆叠小图标 + `N 个终端运行中`，整个 banner 点击 push `TerminalShellPage`。

### 列表

- ListTile → Card 卡片样式
- 主标题：服务器名（无名时回退 host）；左侧绿色小点表示该 host 已有 session
- 副标题：`username@host:port`
- chip 行：authType、group（仅非空时）、`expired`（红色）
- 行尾按钮：
  - host 已有 session：`进入`，点击 `setActive` 到该 host 的 session 并 push 终端页
  - host 未连接：`连接`，点击取参数 + `openSession` + push 终端页
  - 不可连接（`!isConfig` 或 `expired`）：禁用并显示 `未配置` / `已过期`

### 分组

按 `group` 字段分组渲染（sticky header），未分组归"默认"组；分组之间组间距更明显。

### 顶部搜索框

实时过滤 name / host / username / tag / group。

### 其它

- 连接中：行内替换连接按钮为 `CircularProgressIndicator`
- 退出登录二次确认 `AlertDialog`
- 空 / 错误态使用统一组件

## 登录页

- 顶部 logo / 标题区 + 副标题
- 密码字段加可见切换（suffix `IconButton`）
- 服务地址 / 用户名 / 密码 IME action 串联：next → next → done(submit)
- HTTP 警告改 inline banner，确认一次后记入状态，不再每次弹窗
- 错误信息改为带图标的容器，不再裸文本
- 字段间距统一为 12

## 跨页公共体验

### 主题

- `ThemeMode.system`
- `ColorScheme.fromSeed(seedColor: Colors.indigo)` 双套（light / dark）
- 暗色下文本 / 分隔线 / 卡片层级统一

### 401 / 403 自动登出

- `ApiClient` 把 401/403 的 `DioException` 抛 `UnauthorizedFailure extends ApiFailure`
- App 根注册 `onSessionExpired`：清 token + sessionCookie + deviceId（保留 serverAddress / username / savePassword / password 偏好），回登录页
- 列表页与 SSH 凭据接口捕获 `UnauthorizedFailure` 后调用 `onSessionExpired`

### 通用组件

`LoadingView`、`EmptyView`、`ErrorView`，居中布局，可选标题 + 副标题 + 行动按钮。

## Flutter Structure 调整

```text
mobile/lib/
  app.dart
  main.dart

  core/
    api/...
    crypto/...
    storage/...
    ui/
      loading_view.dart
      empty_view.dart
      error_view.dart
      stacked_sessions_icon.dart
      anchored_overlay_menu.dart
    utils/...

  features/
    auth/...
    servers/
      server_list_page.dart
      server_card.dart
      server_repository.dart
      server_model.dart
    terminal/
      terminal_session.dart
      terminal_session_manager.dart
      terminal_shell_page.dart
      terminal_toolbar.dart
      terminal_shortcut_bar.dart
      ssh_connection_config.dart
      ssh_terminal_controller.dart
```

`features/terminal/terminal_page.dart` 删除。

## Testing

新增 / 修改：

Dart 单测：

- `TerminalSessionManager`：open / close / setActive / 状态流转 / 关闭最后一个
- `SshTerminalController`：reconnect 时复用同一 Terminal、scrollback 累积（用 fake transport）
- `EasyNodeAppBootstrap`：登录态恢复（成功路径 / 401 路径 / 缺字段路径）

Flutter widget 测：

- `TerminalShellPage`：堆叠图标菜单展开 / `+` 菜单展开 / 关闭最后一个 session 自动 pop / 断线状态显示
- `ServerListPage`：分组渲染 / 搜索过滤 / 已连接 host 显示绿点 / 顶部 banner 行为
- `LoginPage`：密码可见切换 / 初始密码回填 / HTTP inline banner

后端：未改后端，不新增 server 测试。

## Migration

- 删除 `mobile/lib/features/terminal/terminal_page.dart`
- 路由从 `MaterialPageRoute(TerminalPage)` 切到 `TerminalShellPage`
- 从单 session push → 改为 manager.openSession + push shell 页
