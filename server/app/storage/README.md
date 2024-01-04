# host-list.json

> 存储服务器基本信息

# key.json

> 用于加密的密钥相关

# ssh-record.json

> ssh密钥记录(加密存储)

# email.json

> 邮件配置

- port: 587 --> secure: false
```json
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

# notify.json

> 通知配置

# group.json

> 服务器分组配置
