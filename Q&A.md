# 用于收集一些疑难杂症

- 欢迎pr~

## 甲骨文CentOS7/8启动服务失败

> 先关闭SELinux

```shell
vi /etc/selinux/config
SELINUX=enforcing 
// 修改为禁用
SELINUX=disabled
```

> 重启：`reboot`，再使用一键脚本安装

> 查看SELinux状态：sestatus

## 甲骨文ubuntu20.04客户端服务启动成功，无法连接？

> 端口未开放：`iptables -I INPUT -s 0.0.0.0/0 -p tcp --dport 22022 -j ACCEPT`

