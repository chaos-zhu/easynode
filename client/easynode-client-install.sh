#!/bin/bash

if [ "$(id -u)" != "0" ] ; then
  echo "***********************请切换到root再尝试执行***********************"
	exit 1
fi

clientPort=${clientPort:-22022}
SERVER_NAME=easynode-client
FILE_PATH=/root/local/easynode-client
SERVICE_PATH=/etc/systemd/system
CLIENT_VERSION=client-2024-10-13 # 目前监控客户端版本发布需手动更改为最新版本号
SERVER_PROXY="https://ghfast.top/"

if [ ! -z "$1" ]; then
  clientPort=$1
fi

echo "***********************开始安装EasyNode监控客户端端,当前版本号: ${CLIENT_VERSION}, 端口: ${clientPort}***********************"

systemctl status ${SERVER_NAME} > /dev/null 2>&1
if [ $? != 4 ]
then
  echo "***********************停用旧服务***********************"
	systemctl stop ${SERVER_NAME}
	systemctl disable ${SERVER_NAME}
	systemctl daemon-reload
fi

if [ -f "${SERVICE_PATH}/${SERVER_NAME}.service" ]
then
  echo "***********************移除旧服务***********************"
  chmod 777 ${SERVICE_PATH}/${SERVER_NAME}.service
	rm -Rf ${SERVICE_PATH}/${SERVER_NAME}.service
	systemctl daemon-reload
fi

if [ -d ${FILE_PATH} ]
then
  echo "***********************移除旧文件***********************"
  chmod 777 ${FILE_PATH}
	rm -Rf ${FILE_PATH}
fi

# 开始安装

echo "***********************创建文件PATH***********************"
mkdir -p ${FILE_PATH}

echo "***********************下载开始***********************"

ARCH=$(uname -m)

echo "***********************系统架构: $ARCH***********************"
if [ "$ARCH" = "x86_64" ] ; then
  DOWNLOAD_FILE_URL="${SERVER_PROXY}https://github.com/chaos-zhu/easynode/releases/download/${CLIENT_VERSION}/easynode-client-x64"
elif [ "$ARCH" = "aarch64" ] ; then
  DOWNLOAD_FILE_URL="${SERVER_PROXY}https://github.com/chaos-zhu/easynode/releases/download/${CLIENT_VERSION}/easynode-client-arm64"
else
  echo "不支持的架构：$ARCH. 只支持x86_64和aarch64，其他架构请自行构建"
  exit 1
fi

# -O 指定路径和文件名(这里是二进制文件, 不需要扩展名)
wget -O ${FILE_PATH}/${SERVER_NAME} --no-check-certificate --no-cache ${DOWNLOAD_FILE_URL}
if [ $? != 0 ]
then
  echo "***********************下载${SERVER_NAME}失败***********************"
  exit 1
fi

DOWNLOAD_SERVICE_URL="${SERVER_PROXY}https://raw.githubusercontent.com/chaos-zhu/easynode/main/client/easynode-client.service"

wget -O ${FILE_PATH}/${SERVER_NAME}.service --no-check-certificate --no-cache ${DOWNLOAD_SERVICE_URL}

if [ $? != 0 ]
then
  echo "***********************下载${SERVER_NAME}.service失败***********************"
  exit 1
fi

echo "***********************下载成功***********************"

# echo "***********************设置权限***********************"
chmod +x ${FILE_PATH}/${SERVER_NAME}
chmod 777 ${FILE_PATH}/${SERVER_NAME}.service

sed -i "s/clientPort=22022/clientPort=${clientPort}/g" ${FILE_PATH}/${SERVER_NAME}.service

# echo "***********************移动service&reload***********************"
mv ${FILE_PATH}/${SERVER_NAME}.service ${SERVICE_PATH}

# echo "***********************daemon-reload***********************"
systemctl daemon-reload

echo "***********************启动服务***********************"
systemctl start ${SERVER_NAME}

# echo "***********************设置开机启动***********************"
systemctl enable ${SERVER_NAME}

echo "***********************安装成功***********************"
