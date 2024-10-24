# EasyNode

  <!-- - [功能](#功能)
  - [安装](#安装)
  - [监控服务安装](#监控服务安装)
  - [版本日志](#版本日志)
  - [开发](#开发)
  - [QA](#QA)
  - [安全与建议](#安全与建议)
  - [捐赠](#捐赠)
  - [License](#license) -->

## 功能

- [x] 功能完善的**SSH终端**&**SFTP**
- [x] 批量**导入导出**实例(Xshell&FinalShell&EasyNode)
- [x] **实例分组**
- [x] **凭据托管**
- [x] **多渠道通知**
- [x] **脚本库**
- [x] **批量指令**
- [x] **终端主题背景自定义**

![实例面板](./doc_images/merge.gif)

## 安装

- 默认账户密码 `admin/admin`
- web端口：8082

### docker镜像

```shell
docker run -d -p 8082:8082 --name=easynode --restart=always -v /root/easynode/db:/easynode/app/db chaoszhu/easynode
```
环境变量：
- `PLUS_KEY`: 激活PLUS功能的授权码
- `DEBUG`: 启动debug日志 0：关闭 1：开启, 默认关闭
- `ALLOWED_IPS`: 可以访问服务的IP白名单, 多个使用逗号分隔, 支持填写部分ip前缀, 例如: `-e ALLOWED_IPS=127.0.0.1,196.168`

### 手动部署

依赖Nodejs版本 > 20+

```shell
git clone https://github.com/chaos-zhu/easynode
cd easynode
yarn
cd web
yarn build
mv dist/* ../server/app/static
cd ../server
yarn start
# 后台运行需安装pm2
pm2 start index.js --name easynode-server
```

---

## 监控服务安装

- 监控服务用于实时向服务端推送**系统、公网IP、CPU、内存、硬盘、网卡**等基础信息，不安装不影响使用面板，但是无法实时同步cpu占用、实时网速、硬盘容量等实用信息。

- 默认端口：**22022**

> 安装

```shell
# 使用默认端口22022安装
curl -o- https://ghp.ci/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh | bash

# 使用自定义端口安装, 例如54321
curl -o- https://ghp.ci/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh | bash -s -- 54321
```

> 卸载

```shell
curl -o- https://ghp.ci/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-uninstall.sh | bash
```

> 查看监控服务状态：`systemctl status easynode-client`
>
> 查看监控服务日志: `journalctl --follow -u easynode-client`
>
> 查看详细日志：journalctl -xe

---

## 开发

1. 拉取代码，环境 `nodejs>=20`
2. cd到项目根目录，`yarn install` 执行安装依赖
3. `yarn dev`启动项目
4. web: `http://localhost:18090/`

## 版本日志

- [CHANGELOG](./CHANGELOG.md)

## QA

- [QA](./Q%26A.md)

## 安全与建议

首先声明，任何系统无法保障没有bug的存在，EasyNode也一样。

面板提供MFA2功能，并且可配置访问此服务的IP白名单, 如需加强可以使用**iptables**进一步限制IP访问。
如果需要更高级别的安全性，建议面板服务不要暴露到公网。

webssh与监控服务都将以`该服务器作为中转`。中国大陆用户建议使用香港、新加坡、日本、韩国等地区的低延迟服务器来安装服务端面板

## 捐赠

如果您认为此项目帮到了您, 您可以请我喝杯阔乐~

![wx](./doc_images/wx.jpg)

## License

[MIT](LICENSE). Copyright (c).

![访问数](https://profile-counter.glitch.me/easynode/count.svg)
