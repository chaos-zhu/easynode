FROM node:20.16-alpine3.20
WORKDIR /easynode
COPY . .
RUN yarn

WORKDIR /easynode/web
RUN yarn build
RUN mv dist/* ../server/app/static

WORKDIR /easynode/server
ENV HOST 0.0.0.0
EXPOSE 8082
CMD [ "npm", "start" ]
