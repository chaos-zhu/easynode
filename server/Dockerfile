FROM node:16.15.0-alpine3.14
ARG TARGET_DIR=/easynode-server
WORKDIR ${TARGET_DIR}
RUN yarn config set registry https://registry.npm.taobao.org
COPY package.json ${TARGET_DIR}
COPY yarn.lock ${TARGET_DIR}
RUN yarn
COPY . ${TARGET_DIR}
ENV HOST 0.0.0.0
EXPOSE 8082
EXPOSE 8083
EXPOSE 22022
CMD ["npm", "run", "server"]
