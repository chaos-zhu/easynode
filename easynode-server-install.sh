#!/bin/bash

if [ "$(id -u)" != "0" ] ; then
  echo "***********************请切换到root再尝试执行***********************"
	exit 1
fi

# 编写中...
echo '开始安装nvm'

rm -rf /root/.nvm

# 国内
bash -c "$(curl -fsSL https://gitee.com/chaoszhu_0/nvm-cn/raw/master/install.sh)"
# 国外
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/chaos-zhu/nvm-cn/master/install.sh)" 

if [ $? != "0" ] ; then
 echo '安装失败'
 exit 1
fi

. /root/.nvm/nvm.sh

echo "nvm version: $(nvm -v)"

export VM_NODEJS_ORG_MIRROR=https://npm.taobao.org/mirrors/node

echo '开始安装node&npm'

nvm install --lts

echo "node version: $(node -v) 安装成功"
echo "npm version: $(npm -v) 安装成功"

echo '开始安装pm2'
npm config set registry https://registry.npm.taobao.org 
npm i -g pm2

echo "pm2 version: $(pm2 -v) 安装成功"

echo '开始下载EasyNode'

DOWNLOAD_FILE_URL="https://ghproxy.com/https://github.com/chaos-zhu/easynode/releases/download/v1.0/easynode-server.zip"
SERVER_NAME=easynode-server
SERVER_ZIP=easynode-server.zip
FILE_PATH=/root
wget -O ${FILE_PATH}/${SERVER_ZIP} --no-check-certificate --no-cache ${DOWNLOAD_FILE_URL}

if [ $? != 0 ]
then
  echo "***********************下载EasyNode.zip失败***********************"
  exit 1
fi

echo '开始解压'

unzip -o -d ${FILE_PATH}/${SERVER_NAME} ${SERVER_ZIP}

cd ${FILE_PATH}/${SERVER_NAME} || exit

echo '安装依赖'

npm i -g yarn
yarn

echo '启动服务'

pm2 start ${FILE_PATH}/${SERVER_NAME}/app/main.js
