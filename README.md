# EasyNode

> [!WARNING]
> 初次部署EasyNode，登录系统后务必记得修改默认账户密码 `admin/admin`！

> 强烈建议使用 **iptables** 限制IP访问，谨慎暴露面板服务到公网。

<!-- > [!NOTE]
> webssh与监控服务都将以`该服务器作为中转`。中国大陆连接建议使用香港、新加坡、日本、韩国等地区的低延迟服务器来安装服务端 -->

  - [功能](#功能)
  - [安装](#安装指南)
    - [服务端安装](#服务端安装)
    - [监控服务安装](#监控服务安装)
  - [版本日志](#版本日志)
  - [开发](#开发)
  - [Q&A](#Q&A)
  - [捐赠](#捐赠)
  - [License](#license)

## 功能

- [x] webssh终端&SFTP
- [x] 批量导入(Xshell&FinalShell)
- [x] 实例分组
- [x] 凭据托管
- [x] 邮件通知
- [x] 服务器状态推送
- [x] 脚本库
- [x] 批量指令
- [ ] 自定义终端主题

![实例面板](./doc_images/merge.gif)

## 安装

### 服务端安装

- 占用端口：8082  推荐使用docker镜像安装

#### Docker部署

```shell
docker run -d --net=host --name=easynode-server -v $PWD/easynode/db:/easynode/app/db chaoszhu/easynode
# 容器支持使用-p 8082:8082映射端口, 但是无法记录登录IP
```
访问：http://yourip:8082

#### 手动部署

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

访问：http://yourip:8082

- 查看日志：`pm2 log easynode-server`
- 启动服务：`pm2 start easynode-server`
- 停止服务：`pm2 stop easynode-server`
- 删除服务：`pm2 delete easynode-server`

---

### 监控服务安装

- 监控服务用于实时向服务端推送**系统、公网IP、CPU、内存、硬盘、网卡**等基础信息，不安装不影响使用面板，但是无法实时同步cpu占用、实时网速、硬盘容量等有用信息。

- 占用端口：**22022**

> 安装

```shell
curl -o- https://mirror.ghproxy.com/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-install.sh | bash
```

> 卸载

```shell
curl -o- https://mirror.ghproxy.com/https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client-uninstall.sh | bash
```

> 查看监控服务状态：`systemctl status easynode-client`
>
> 查看监控服务日志: `journalctl --follow -u easynode-client`
>
> 查看详细日志：journalctl -xe

---

## 版本日志

- [CHANGELOG](./CHANGELOG.md)

## 开发

1. 拉取代码，环境 `nodejs``>=20`
2. cd到项目根目录，`yarn install` 执行安装依赖
3. `yarn dev`启动项目
4. web: `http://localhost:18090/`

## Q&A

- [Q&A](./Q%26A.md)

## 捐赠

如果您认为此项目帮到了您, 您可以请我喝杯阔乐~

![wx](./doc_images/wx.jpg)

## License

[MIT](LICENSE). Copyright (c).
