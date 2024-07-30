db目录，初始化后自动生成

**host.db**

> 存储服务器基本信息

**key.db**

> 用于加密的密钥相关

**credentials.db**

> ssh密钥记录(加密存储)

**email.db**

> 邮件配置

- port: 587 --> secure: false
```db
// Gmail调试不通过, 暂缓
{
  "name": "Google邮箱",
  "target": "google",
  "host": "smtp.gmail.com",
  "port": 465,
  "secure": true,
  "tls": {
    "rejectUnauthorized": false
  }
}
```

**notify.db**

> 通知配置

**group.db**

> 服务器分组配置
