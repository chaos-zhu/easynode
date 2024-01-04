# 面板服务端

- 基于Koa

## docker

<!-- 修改版本号 -->
- 构建镜像：docker build -t chaoszhu/easynode:v1.1 .
- 推送镜像：docker push chaoszhu/easynode:v1.1

> `docker run -d --net=host easynode-server`
<!-- > `docker run -d -p 8888:8082 -p 22022:22022 easynode-server` -->

## 遇到的问题

> MaxListenersExceededWarning: Possible EventEmitter memory leak detected. 11 input listeners added to [Socket]. Use emitter.setMaxListeners() to increase limit
- ssh连接数过多(默认最多11个)
- 每次连接新建一个vps实例，断开则销毁

> Error signing data with key: error:0D07209B:asn1 encoding routines:ASN1_get_object:too long
- 经比对，ssh的rsa密钥在前端往后端的存储过程中丢失了部分字符

> 获取客户端信息：跨域请求客户端系统信息，建立ws socket实时更新网络
- 问题：服务端前端套上https后，前端无法请求客户端(http)的信息, 也无法建立ws socket连接(原因是https下无法建立http/ws协议请求)
- 方案1: 所有客户端与服务端通信，再全部由服务端与前端通信(考虑：服务端/客户端性能问题). Node实现http+https||nginx转发实现https
- 方案2: 给所有客户端加上https(客户端只有ip，没法给个人ip签订证书)

## 构建运行包

### 坑

> log4js: 该module使用到了fs.mkdir()等读写api，pkg打包后的环境不支持，设置保存日志的目录需使用process.cwd()】

> win闪退: 在linux机器上构建可查看输出日志

## 客户端

> **构建客户端服务, 后台运行** `nohup ./easynode-server &`

> 功能：服务器基本信息【ssh信息保存在主服务器】
