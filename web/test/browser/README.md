# 终端浏览器回归测试

运行 `yarn workspace web run test:terminal:browser`。需要可解析的 `playwright` 包，可通过 `NODE_PATH` 指向已有安装目录。浏览器默认使用 macOS 上已安装的 Chrome，否则使用 Playwright 的 Chromium；可用 `CHROME_PATH` 指定浏览器可执行文件。

测试启动临时本地 Vite 服务，在无头浏览器中加载真实终端页面组件、Vue、Element Plus、xterm 及其插件。SSH 传输和 API 使用模拟数据，SFTP、AI、状态栏等辅助组件使用占位组件，不需要账号，也不会连接真实主机。此测试验证终端组件交互，不替代完整应用与真实 SSH 的集成测试。

覆盖三主机单窗口布局、关闭非活动标签、反复切换布局、挂起一个分屏并保留其他会话、键盘输入路由和组件卸载。设置 `TERMINAL_SCREENSHOT` 为输出文件路径，可保存三主机单窗口截图。

普通 `yarn workspace web test` 包含真实 xterm 插件销毁测试，无需浏览器；浏览器测试单独运行。
