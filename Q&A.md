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

## 终端中复制粘贴失败？

> 可能是浏览器出于安全考虑，阻止了访问剪贴板的API，导致在Web终端中无法复制粘贴。

**解决：**

> 1. **使用HTTPS访问**：剪贴板访问通常只在HTTPS下允许（localhost除外），确认其使用的是加密连接。

> 2. **使用工具栏功能**：开启终端页面的`工具栏`后选择`脚本库`项，在`脚本编辑器`中粘贴然后点击`发送到终端`。

> 3. **检查站点权限设置**：确认浏览器未阻止剪贴板的访问权限，或尝试在其他浏览器中打开。

> 4. **尝试刷新页面**：如果是偶发性问题或可通过刷新来解决。

## Docker 环境下无法连接纯 IPv6 服务器

> 大概率是 Docker 未启用 IPv6，导致容器内应用虽然运行正常，但没有可用的 IPv6 网络能力，因此无法访问纯 IPv6 目标。

### 解决

#### 方案一：在 Docker Daemon 中启用 IPv6

1. 为 Docker 配置固定的 IPv6 子网，例如在 Docker 的 `daemon.json` 中加入：

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}
```

2. 重启 Docker 服务后重新创建容器，再测试 SSH 连接。

3. 可进入容器内执行 `ping6`、`curl -6` 或直接测试 SSH 到目标 IPv6 地址，确认容器内 IPv6 网络已生效。

> 如果使用的是 `docker-compose`，也需要确认对应网络已开启 IPv6 配置。

#### 方案二：使用支持ipv6的服务器作为跳板机或者socket代理

> 编辑服务器设置，启用跳板机(需激活plus)
