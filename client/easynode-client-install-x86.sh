#!/bin/bash

if [ "$(id -u)" != "0" ] ; then
  echo "***********************请切换到root再尝试执行***********************"
	exit 1
fi

SERVER_NAME=easynode-client
FILE_PATH=/root/local/easynode-client
SERVICE_PATH=/etc/systemd/system
SERVER_VERSION=v1.0

echo "***********************开始安装 easynode-client_${SERVER_VERSION}***********************"

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
DOWNLOAD_FILE_URL="https://mirror.ghproxy.com/https://github.com/chaos-zhu/easynode/releases/download/v1.1/easynode-client-x86"
DOWNLOAD_SERVICE_URL="https://mirror.ghproxy.com/https://raw.githubusercontent.com/chaos-zhu/easynode/v1.1/client/easynode-client.service"

# -O 指定路径和文件名(这里是二进制文件, 不需要扩展名)
wget -O ${FILE_PATH}/${SERVER_NAME} --no-check-certificate --no-cache ${DOWNLOAD_FILE_URL}
if [ $? != 0 ]
then
  echo "***********************下载${SERVER_NAME}失败***********************"
  exit 1
fi

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

# echo "***********************移动service&reload***********************"
mv ${FILE_PATH}/${SERVER_NAME}.service ${SERVICE_PATH}

# echo "***********************daemon-reload***********************"
systemctl daemon-reload

echo "***********************准备启动服务***********************"
systemctl start ${SERVER_NAME}

if [ $? != 0 ]
then
  echo "***********************${SERVER_NAME}.service启动失败***********************"
  echo "***********************可能是服务器开启了SELinux, 参见Q&A***********************"
  exit 1
fi
echo "***********************服务启动成功***********************"

# echo "***********************设置开机启动***********************"
systemctl enable ${SERVER_NAME}

echo "***********************安装成功***********************"
