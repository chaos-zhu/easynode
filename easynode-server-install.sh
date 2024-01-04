#!/bin/bash

if [ "$(id -u)" != "0" ] ; then
  echo "***********************请切换到root再尝试执行***********************"
	exit 1
fi

echo "***********************检测node环境***********************"
node -v
if [ $? != 0 ]
then
  echo "未安装node运行环境"
  exit 1
fi
echo "已安装"


echo "***********************检测pm2守护进程***********************"
pm2 list
if [ $? != 0 ]
then
  echo "未安装pm2,正在安装..."
  npm i -g pm2
fi
echo "已安装"

echo "***********************开始下载EasyNode***********************"

DOWNLOAD_FILE_URL="https://ghproxy.com/https://github.com/chaos-zhu/easynode/releases/download/v1.2.1/easynode-server.zip"
SERVER_NAME=easynode-server
SERVER_ZIP=easynode-server.zip
FILE_PATH=/root
wget -O ${FILE_PATH}/${SERVER_ZIP} --no-check-certificate --no-cache ${DOWNLOAD_FILE_URL}

if [ $? != 0 ]
then
  echo "下载EasyNode.zip失败,请检查网络环境或稍后再试"
  exit 1
fi
echo "下载成功"

echo '***********************开始解压***********************'

unzip -o -d ${FILE_PATH}/${SERVER_NAME} ${SERVER_ZIP}
if [ $? != 0 ]
then
  echo "解压失败, 请确保已安装zip、tar基础工具"
  exit 1
fi
echo "解压成功"

cd ${FILE_PATH}/${SERVER_NAME} || exit

echo '***********************开始安装依赖***********************'
yarn -v
if [ $? != 0 ]
then
  echo "未安装yarn管理工具,正在安装..."
  npm i -g yarn
fi
yarn

if [ $? != 0 ]
then
  echo "yarn安装失败，请检测网络环境. 使用大陆vps请执行以下命令设置镜像源，再重新运行该脚本：npm config set registry https://registry.npm.taobao.org
"
fi
echo "依赖安装成功"

echo '启动服务'

pm2 start ${FILE_PATH}/${SERVER_NAME}/app/main.js --name easynode-server

echo '查看日志请输入: pm2 log easynode-server'
