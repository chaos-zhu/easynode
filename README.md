<div align="center">

# EasyNode

_✨ 一个多功能Linux服务器WEB终端面板(webSSH&webSFTP) ✨_

</div>

<p align="center">
  <a href="https://github.com/chaos-zhu/easynode/releases/latest">
    <img src="https://img.shields.io/github/v/release/chaos-zhu/easynode?color=brightgreen" alt="release">
  </a>
  <a href="https://github.com/chaos-zhu/easynode/actions">
    <img src="https://img.shields.io/github/actions/workflow/status/chaos-zhu/easynode/docker-builder.yml?branch=main" alt="deployment status">
  </a>
  <a href="https://hub.docker.com/repository/docker/chaoszhu/easynode">
    <img src="https://img.shields.io/docker/pulls/chaoszhu/easynode?color=brightgreen" alt="docker pull">
  </a>
  <a href="https://github.com/chaos-zhu/easynode/releases/latest">
    <img src="https://img.shields.io/github/downloads/chaos-zhu/easynode/total?color=brightgreen&include_prereleases" alt="release">
  </a>
  <a href="https://raw.githubusercontent.com/chaos-zhu/easynode/main/LICENSE">
    <img src="https://img.shields.io/github/license/chaos-zhu/easynode?color=brightgreen" alt="license">
  </a>
</p>

<p align="center">
  <a href="#功能">功能</a>
  ·
  <a href="#面板展示">面板展示</a>
  ·
  <a href="#项目部署">项目部署</a>
  ·
  <a href="#监控服务安装">监控服务安装</a>
  ·
  <a href="#安全与建议">安全与建议</a>
  ·
  <a href="#常见问题">常见问题</a>
  <!-- ·
  <a href="#Plus功能">Plus版功能</a> -->
</p>

## 功能

+ [x] 功能完善的**SSH终端**&**SFTP**
+ [x] 批量导入、导出、编辑服务器配置、脚本等
+ [x] 脚本库
+ [x] 实例分组
+ [x] 凭据托管
+ [x] 多渠道通知
+ [x] 批量下发指令
+ [x] 自定义终端主题

## 面板展示

![面板展示](./doc_images/merge.gif)

## 项目部署

- 默认账户密码 `admin/admin`
- web端口：8082

### docker镜像

```shell
docker run -d -p 8082:8082 --restart=always -v /root/easynode/db:/easynode/app/db chaoszhu/easynode
```
环境变量：
- `DEBUG`: 启动debug日志 0：关闭 1：开启, 默认关闭
- `ALLOWED_IPS`: 可以访问服务的IP白名单, 多个使用逗号分隔, 支持填写部分ip前缀, 例如: `-e ALLOWED_IPS=127.0.0.1,196.168`

## 监控服务安装

- 监控服务用于实时向服务端&web端推送**系统、公网IP、CPU、内存、硬盘、网卡**等基础信息

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


## 安全与建议

首先声明，任何系统无法保障没有bug的存在，EasyNode也一样。

面板提供MFA2功能，并且可配置访问此服务的IP白名单, 如需加强可以使用**iptables**进一步限制IP访问。
如果需要更高级别的安全性，建议面板服务不要暴露到公网。

webssh与监控服务都将以`该服务器作为中转`。中国大陆用户建议使用香港、新加坡、日本、韩国等地区的低延迟服务器来安装服务端面板

## 常见问题

- [QA](./Q%26A.md)

<!-- ## Plus版功能

- 跳板机功能,拯救被墙实例与龟速终端输入
- 本地socket断开自动重连,无需手动重新连接
- 批量修改实例配置(优化版)
- 脚本库批量导出导入
- 凭据管理支持解密带密码保护的密钥
- 提出的功能需求享有更高的开发优先级 -->
