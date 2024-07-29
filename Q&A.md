# Q&A

## ssh连接失败

首先确定用户名/密码/密钥没错，接着排查服务端ssh登录日志，例如Debian12 `journalctl -u ssh -f`

如果出现类似以下日志:
```shell
Jul 10 12:29:11 iZ2ze5f4ne9xf8n3h5Z sshd[8020]: userauth_pubkey: signature algorithm ssh-rsa not in PubkeyAcceptedAlgorithms [preauth]
```

说明客户端 `ssh-rsa` 签名算法不在 `PubkeyAcceptedAlgorithms` 列表中，目标服务器不接受 ssh-rsa 签名算法的公钥认证。

**解决： **
编辑 /etc/ssh/sshd_config 文件，添加或修改以下配置
```shell
PubkeyAcceptedAlgorithms +ssh-rsa
```
重新启动 SSH 服务： `sudo systemctl restart sshd`

## CentOS7/8启动服务失败

> 先关闭SELinux

```shell
vi /etc/selinux/config
SELINUX=enforcing
# 修改为禁用
SELINUX=disabled
```

> 重启：`reboot`，再使用一键脚本安装

> 查看SELinux状态：sestatus

## 客户端服务启动成功，无法连接？

> 1. 检查防火墙配置

> 2. iptables端口未开放：`iptables -I INPUT -s 0.0.0.0/0 -p tcp --dport 22022 -j ACCEPT` 或者 `rm -rf /etc/iptables && reboot`
