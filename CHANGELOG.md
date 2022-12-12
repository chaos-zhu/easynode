## [1.2.1](https://github.com/chaos-zhu/easynode/releases) (2022-12-12)

### Features

* 新增支持终端长命令输入模式 ✔
* 新增前端静态文件缓存 ✔

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
