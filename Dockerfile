FROM node:20.16-alpine3.20 AS builder_web
WORKDIR /easynode/web
COPY ./web .
COPY yarn.lock .
RUN yarn
RUN yarn build
# RUN find ../server/app/static -type f ! -name '.gitkeep' -exec rm -f {} +
# RUN mv dist/* ../server/app/static

# 在这里加上builder_server
FROM node:20.16-alpine3.20 AS builder_server
WORKDIR /easynode/server
COPY ./server .
COPY yarn.lock .
COPY --from=builder_web /easynode/web/dist ./app/static
RUN yarn

FROM node:20.16-alpine3.20
WORKDIR /easynode
COPY --from=builder_server /easynode/server .
ENV HOST 0.0.0.0
EXPOSE 8082
CMD ["npm", "start"]
