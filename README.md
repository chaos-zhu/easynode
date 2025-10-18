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
</p>

## 功能

+ [x] 功能完善的**SSH终端**&**SFTP**
+ [x] 跳板机功能,拯救被墙实例与加速跨国终端输入
+ [x] AI对话组件，对话联动终端
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

- v3.1.0版本开始用户名密码不再是admin/admin. 需查看**终端日志**，另外登录后请及时修改，避免日志残留敏感信息。请牢记账号密码，出于安全原因，不提供一键重置密码的脚本
- 默认web端口：**8082**


### docker-compose部署-自动更新（推荐）

```shell
# 1. 创建easynode目录
mkdir -p /root/easynode && cd /root/easynode

# 2. 下载docker-compose.yml文件
wget https://git.221022.xyz/https://raw.githubusercontent.com/chaos-zhu/easynode/main/docker-compose.yml

# 3. 启动服务
docker-compose up -d
```


### docker镜像

**注意！！！**

**v3.5.0版本新增RDP连接windows服务器功能，此功能依赖单独的guacd服务**

- 如果你不知道guacd服务，请使用上面的 docker-compose.yml 进行部署

- 如果你不想使用 docker-compose.yml 进行部署，请配置环境变量 `GUACD_HOST` 和 `GUACD_PORT`

```shell
# GUACD_HOST: 自建 guacd 服务 IP【此处127.0.0.1仅为示例,需自建服务】
# GUACD_PORT: 自建 guacd 服务端口
docker run -d \
  -p 8082:8082 \
  --restart=always \
  -v /root/easynode/db:/easynode/app/db \
  -e GUACD_HOST=127.0.0.1 \
  -e GUACD_PORT=4822 \
  chaoszhu/easynode
```

环境变量：
- `GUACD_HOST`: 自建guacd服务IP
- `GUACD_PORT`: 自建guacd服务PORT
- `DEBUG`: 启动debug日志 0：关闭 1：开启, 默认关闭

注意: **docker默认不启用ipv6，请自行配置或者使用支持ipv6的跳板机中转.**

## 监控服务安装

！v3.2.0开始不再需要安装监控服务端，低于此版本的面板不再提供客户端下载，建议升级到此版本。
已经安装过监控服务的服务器建议使用内置一键脚本卸载：`脚本库 -> easynode监控服务卸载`

## 安全与建议

首先声明，任何系统无法保障没有bug的存在，EasyNode也一样。

请妥善利用面板提供MFA2、IP白名单等安全功能, 如需加强可以使用**iptables**进一步限制IP访问。

如果需要更高级别的安全性，建议面板服务不要暴露到公网。

webssh与监控服务都将以`该服务器作为中转`。中国大陆用户建议使用香港、新加坡、日本、韩国等地区的低延迟服务器来安装服务端面板。

## 常见问题

- [QA](./Q%26A.md)

## 测试服务由以下厂商赞助

CDN acceleration and security protection for this project are sponsored by Tencent EdgeOne: EdgeOne offers a long-term free plan with unlimited traffic and requests, covering Mainland China nodes, with no overage charges. Interested friends can click the link below to claim it. [Best Asian CDN, Edge, and Secure Solutions - Tencent EdgeOne](https://edgeone.ai/zh?from=github)
[![EdgeOne Logo](https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png)](https://edgeone.ai/?from=github)

[![Powered by DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")


[![image](https://img.shields.io/badge/NodeSupport-YXVM-red)](https://yxvm.com/)

![Image](https://github.com/user-attachments/assets/a50409e4-9394-4a59-a125-18ffe64c5fb0)


