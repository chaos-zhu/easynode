#!/usr/bin/env bash

if [ "$(id -u)" != "0" ] ; then
  echo "***********************请切换到root再尝试执行***********************"
	exit 1
fi

SERVER_NAME=easynode-client
FILE_PATH=/root/local/easynode-client
SERVICE_PATH=/etc/systemd/system

echo "*********************** 开始卸载 ***************************"

service ${SERVER_NAME} stop
systemctl disable ${SERVER_NAME}

echo "*********************** 移除文件 ***************************"

if [ -d "${FILE_PATH}" ]
then
	rm -Rf ${FILE_PATH}
fi

echo "*********************** 移除服务 ***************************"
if [ -f "${SERVICE_PATH}/${SERVER_NAME}.service" ]
then
	rm -Rf ${SERVICE_PATH}/${SERVER_NAME}.service
	systemctl daemon-reload
fi

echo "*********************** 卸载完成 ***************************"

# echo "***********************删除脚本***********************"
rm  "$0"