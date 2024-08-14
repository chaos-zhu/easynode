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
