## TODO

* 批量下发后台定时任务
* 移动端Ctrl、Tab的按键面板
* 数据导出(2fa强制)
* 进程管理
* 当前会话连接|w
* 日志打印优化
* 探针接入
* 通知模块重构，支持webhook
* 支持csv模板特定格式导入

## [3.5.1](https://github.com/chaos-zhu/easynode/releases) (2025-10-20)
* 终端默认缓冲区大小提高至10000@zhanghao-njmu
* 支持终端内缓冲区内搜索功能@zhanghao-njmu
* 实例列表-添加实例标识展示(Linux|Win)
* win用户名小于8位字符可能导致连接失败(已添加弹窗提示,暂未定位原因)
* 修复粘贴内容的换行符问题
* ❤️ 特别感谢 @zhanghao-njmu 的功能PR


## [3.5.0](https://github.com/chaos-zhu/easynode/releases) (2025-10-18)
* 🖥️ 支持 RDP 远程 Windows 桌面连接（支持移动端交互 & 剪贴板互动）
* 🧩 脚本库增强：新增脚本执行模式 — 多行脚本@zhanghao-njmu
* 💻 终端增强：输出高亮自定义、配置持久化管理、样式优化、全屏下 bug 修复@zhanghao-njmu
* 📂 SFTP增强：宽度拖拽、个性化显示文件信息列(大小、修改时间、权限、拥有者)@zhanghao-njmu
* ⚙️ 其他优化与bug修复
* ❤️ 特别感谢 @zhanghao-njmu 的功能PR

## [3.4.2](https://github.com/chaos-zhu/easynode/releases) (2025-08-24)
* 🔒鉴权增强
* SFTP连接优化、支持搜索文件(夹)、新建文件(夹)功能名称缓存建议
* 实例列表出现滚动条时出现回到顶部按钮

## [3.4.0](https://github.com/chaos-zhu/easynode/releases) (2025-08-09)
* 🎉新增文件对传功能
* SFTP面板支持手动断开重连
* SFTP loading ui修复
* 禁用MFA2添加验证
* 支持openssh加密密钥
* 点击Logo切换菜单位置
* 换了个新Logo
* 合并通知配置tab

## [3.3.0](https://github.com/chaos-zhu/easynode/releases) (2025-08-04)

* 🎉新增终端连接代理服务
* 状态面板新增服务端至主机ping值
* 优化主机列表&主机表单布局
* 修复最近连接已移除实例保留的bug
* 修复移动端菜单bug
* 修复单窗口模式需重启的bug
* 服务端第层组件升级

## [3.2.0](https://github.com/chaos-zhu/easynode/releases) (2025-07-26)

* 🎉终端状态监控采用原生指令实现(不再依赖客户端上报)
* 终端快速连接更改为最近连接
* 修复全屏功能&单窗口新增聚焦放大终端
* 批量指令支持交互式认证服务器&逻辑重构与修复
* AI组件复制&执行按钮定位位置
* 修复终端脚本不自动执行指令
* 全面移除旧版本sftp&client等服务组件
* 🔒升级底层安全依赖组件(建议升级到此版本)


## [3.1.1](https://github.com/chaos-zhu/easynode/releases) (2025-07-19)

* 🎉终端新增单窗口模式
* SFTP新增cd目录快捷菜单
* 微调终端布局&优化文案&底部栏调整为纯脚本库,支持拖动设定高度
* 状态、SFTP等状态本地记忆
* 修复脚本库与窗口输入同步问题
* 优化终端大小重置后自动滚动到最后一行


## [3.1.0](https://github.com/chaos-zhu/easynode/releases) (2025-07-13)

* 重构终端布局，支持单服务器多屏展示（下版本将上线单窗口模式, 单屏展示连接的多个服务器终端
* 重构SFTP面板，实现全功能交互
* 终端页支持实例分组菜单并支持一键连接分组所有实例
* 优化终端渲染，提升缓存行数至5000
* 已授权ip优化UI并支持一键设置到登录白名单
* AI组件对话编辑功能与字体大小优化
* 其他优化


## [3.0.7](https://github.com/chaos-zhu/easynode/releases) (2025-05-24)

* 新增docker容器功能
* 新增AI对话生成指令支持一键发送到终端
* 新增登录有效期选择
* 新增Sftp支持跳板机连接
* 修复serv00 SFTP无法连接的问题
* 修复MFA验证以0开头无法校验的bug

## [3.0.6](https://github.com/chaos-zhu/easynode/releases) (2025-05-05)

* AI问答支持历史记录&标题生成
* 新增终端选中多功能菜单(一键询问AI、docker容器ID识别快捷操作. 欢迎issue反馈更多快捷功能)
* 添加一些新的内置脚本
* 新增终端链接跳转需按住ctrl|alt键(防止误触)
* 修复粘贴情景下多终端tab同步会话无效bug
* 修复跳板机提示多余空格

## [3.0.5](https://github.com/chaos-zhu/easynode/releases) (2025-04-04)

* 新增AI问答组件及相关配置项,支持deepseekR1、qwq思维链
* 脚本库菜单自定义展示(可在本地设置中配置)
* 支持在面板配置全局API-IP白名单
* 修复终端工具栏高度塌陷
* 修复多页面在内容数量超出视窗时溢出样式问题
* 全局字体优化统一

## [3.0.4](https://github.com/chaos-zhu/easynode/releases) (2025-03-15)

* 新增脚本库分组功能
* 终端页新增脚本库布局
* 优化多行命令编辑器
* 优化终端工具栏布局
* 优化多项新增序号自动累加
* 修复前端连接断开但未释放服务端ssh连接的bug
* 修复终端页面同步会话在自动执行脚本开关为true时自动添加回车的bug

## [3.0.3](https://github.com/chaos-zhu/easynode/releases) (2024-12-22)

* 支持keyboard-interactive服务器验证(serv00验证通过)
* 支持TG Bot通知方式
* 添加web端Plus授权功能
* 修复一些UI问题
* 修复MFA2登录验证码为0开头无法输入的bug

## [3.0.2](https://github.com/chaos-zhu/easynode/releases) (2024-11-20)

* 修复添加实例错误禁用的bug


## [3.0.1](https://github.com/chaos-zhu/easynode/releases) (2024-11-18)

* 修复同IP实例SFTP连接到其他的实例的bug
* 修复一些UI问题


## [3.0.0](https://github.com/chaos-zhu/easynode/releases) (2024-11-09)

* 新增跳板机功能,支持选择多台机器跳转
* 脚本库批量导出导入
* 本地socket断开自动重连,无需手动重新连接
* 支持脚本库模糊搜索功能
* 分组添加实例数量标识
* 优化登录逻辑
* 默认登录有效期更改为当天有效
* 优化脚本库新增脚本时序号自动累加
* 修复一些小bug

## [2.3.0](https://github.com/chaos-zhu/easynode/releases) (2024-10-24)

* 重构本地数据库存储方式(性能提升一个level~)
* 支持MFA2二次登录验证
* 优化了一些页面在移动端的展示
* 修复偶现刷新页面需重新登录的bug


## [2.2.8](https://github.com/chaos-zhu/easynode/releases) (2024-10-20)

### Features

* 兼容移动端UI
* 新增移动端虚拟功能按键映射
* 调整终端功能菜单
* 登录日志本地化储存
* 修复终端选中文本无法复制的bug
* 修复无法展示服务端ping客户端延迟ms的bug
* 修复暗黑模式下的一些样式问题

## [2.2.7](https://github.com/chaos-zhu/easynode/releases) (2024-10-17)

### Features

* 终端连接页新增展示服务端ping客户端延迟ms
* 修复自定义客户端端口默认字符串的bug
* 终端支持快捷设置开关: 快捷复制、快捷粘贴、选中脚本自动执行

## [2.2.6](https://github.com/chaos-zhu/easynode/releases) (2024-10-14)

### Features

* 支持自定义客户端端口,方便穿透内网机器
* 修复监控数据意外注入bug

## [2.2.5](https://github.com/chaos-zhu/easynode/releases) (2024-10-11)

### Features

* 不再对同IP:PORT的实例进行校验
* 支持同IP任意端口的服务器录入
* 支持关闭所有终端连接
* 修复第三方git代理地址

## [2.2.4](https://github.com/chaos-zhu/easynode/releases) (2024-08-31)

### Features

* SFTP支持输入路径跳转

## [2.2.3](https://github.com/chaos-zhu/easynode/releases) (2024-08-20)

### Features

* 添加环境变量 ✔
* 支持IP访问白名单设置 ✔
* 修复一些小bug ✔
* 优化Eslint规则 ✔

## [2.2.2](https://github.com/chaos-zhu/easynode/releases) (2024-08-19)

### Features

* 支持菜单栏的折叠与展开 ✔
* 优化终端回显 ✔
* 优化暗黑模式下滚动条样式 ✔

## [2.2.1](https://github.com/chaos-zhu/easynode/releases) (2024-08-18)

### Features

* 支持暗黑主题切换 ✔
* 批量脚本下发执行结果通知重复的bug ✔
* 修复交换内存占比的bug ✔
* 优化服务端代码引用 ✔
* 修复Code scanning提到的依赖风险 ✔

## [2.2.0](https://github.com/chaos-zhu/easynode/releases) (2024-08-17)

### Features

* 重构通知模块 ✔
* 支持大多数邮箱SMTP配置通知 ✔
* 支持Server酱通知 ✔
* 新增批量指令执行结果提醒 ✔
* 新增终端登录与登录状态提醒 ✔
* 新增服务器到期提醒 ✔
* 修复上传同一个文件无法选择的bug ✔
* 修复终端连接失败抛出异常的bug ✔
* 调整客户端安装脚本 ✔

## [2.1.9](https://github.com/chaos-zhu/easynode/releases) (2024-08-16)

### Features

* 过滤客户端检测更新 ✔

## [2.1.8](https://github.com/chaos-zhu/easynode/releases) (2024-08-15)

### Features

* 终端连接逻辑重写,断线自动重连 ✔
* 终端连接状态展示 ✔
* 终端支持选中复制&右键粘贴 ✔
* 终端设置支持字体大小 ✔
* 终端默认字体样式更改为`Cascadia Code` ✔

## [2.1.7](https://github.com/chaos-zhu/easynode/releases) (2024-08-14)

### Features

* 客户端监控服务支持swap内存交换回传 ✔
* 面板支持展示swap内存交换状态展示 ✔
* 添加初始账户登录警告 ✔

## [2.1.6](https://github.com/chaos-zhu/easynode/releases) (2024-08-13)

### Features

* SFTP支持上传嵌套文件夹 ✔
* 修复面板服务缓存文件夹偶尔不存在的bug  ✔

## [2.1.5](https://github.com/chaos-zhu/easynode/releases) (2024-08-12)

### Features

* 新增终端设置 ✔
* 支持更多终端主题 ✔
* 支持终端背景图片(当前版本只缓存在前端且只可以使用内置背景图片) ✔

## [2.1.4](https://github.com/chaos-zhu/easynode/releases) (2024-08-12)

### Features

* 新增cd全路径命令联动SFTP面板 ✔
* 修复SFTP文件编辑文件名称显示错误的bug ✔

## [2.1.3](https://github.com/chaos-zhu/easynode/releases) (2024-08-11)

### Features

* 修复开启or关闭SFTP功能开关时，终端光标位置错误的bug ✔

## [2.1.2](https://github.com/chaos-zhu/easynode/releases) (2024-08-09)

### Features

* 新增导入导出功能(EasyNode JSON) ✔
* 新增服务器列表排序与排序缓存 ✔
* 优化客户端连接状态展示 ✔
* 优化版本更新提示 ✔

## [2.1.1](https://github.com/chaos-zhu/easynode/releases) (2024-08-05)

### Features

* 支持批量操作：批量修改实例通用信息(ssh配置等)、批量删除、批量安装客户端监控应用 ✔
* 自动化构建镜像 ✔
* 调整&优化面板UI ✔
* 内置常用脚本(逐渐添加中...) ✔

## [2.1.0](https://github.com/chaos-zhu/easynode/releases) (2024-08-02)

### Features

* 支持脚本库功能 ✔
* 支持批量指令下发功能 ✔
* 支持多会话同步指令 ✔
* 重写Dockerfile,大幅减少镜像体积 ✔
* 调整优化面板UI ✔

## [2.0.0](https://github.com/chaos-zhu/easynode/releases) (2024-07-29)

### Features

* 重构前端UI ✔
* 新增多个功能菜单 ✔
* 重构文件储存方式 ✔
* 升级前后端依赖 ✔
* 优化前端工程 ✔
* 修复不同ssh密钥算法登录失败的bug ✔
* 移除上一次IP登录校验的判断 ✔
* 前端工程迁移至项目根目录 ✔
* 添加ssh密钥or密码保存至本地功能 ✔

## [1.2.1](https://github.com/chaos-zhu/easynode/releases) (2022-12-12)

### Features

* 新增支持终端长命令输入模式 ✔
* 新增前端静态文件缓存 ✔
* 【重要】v1.2.1开始移除创建https服务 ✔

### Bug Fixes

* v1.2的若干bug...

## [1.2.0](https://github.com/chaos-zhu/easynode/releases) (2022-09-12)

### Features

* 新增邮件通知: 包括登录面板、密码修改、服务器到期、服务器离线等 ✔
* 支持服务器分组(为新版UI作准备的) ✔
* 面板功能调整，支持http延迟显示、支持服务器控制台直达与到期时间字段 ✔
* 优化终端输入、支持状态面板收缩 ✔
* **全新SFTP功能支持，上传下载进度条展示** ✔
* **支持在线文件编辑与保存** ✔

### Bug Fixes

* v1.1的若干bug...

---

## [1.1.0](https://github.com/chaos-zhu/easynode/releases) (2022-06-27)

### Features

* ssh密钥/密码(采用对称AES+RSA非对称双加密传输与存储)、jwtToken(服务端对称加密传输) ✔
* 加密储存登录密码 ✔
* 登录IP检测机制&历史登录查询✔
* 终端多tab支持✔
* 终端页左侧栏信息✔
* 客户端支持ARM实例✔

### Bug Fixes

* 修复终端展示异常的Bug✔
* 修复保存私钥时第二次选择无效的bug✔
* 修复面板客户端探针断开更新不及时的bug✔
* 修复移除主机未移除ssh密钥信息的bug✔
* 修复服务器排序bug✔
* 解决https下无法socket连接到客户端bug✔

---

## [1.0.0](https://github.com/chaos-zhu/easynode/releases) (2022-06-08)


### Features

* 通过`websocker实时更新`服务器基本信息: 系统、公网IP、CPU、内存、硬盘、网卡等
*  解决`SSH跨端同步`问题——Web SSH
