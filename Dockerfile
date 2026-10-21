FROM node:22.23.4-alpine3.24 AS builder_web
WORKDIR /easynode/web
COPY ./web .
COPY yarn.lock .
RUN yarn
RUN yarn build

FROM node:22.23.4-alpine3.24 AS builder_server
WORKDIR /easynode/server
COPY ./server .
COPY yarn.lock .
COPY --from=builder_web /easynode/web/dist ./app/static
RUN yarn

FROM node:22.23.4-alpine3.24
RUN apk add --no-cache iputils
WORKDIR /easynode
COPY --from=builder_server /easynode/server .
ENV HOST=0.0.0.0
EXPOSE 8082
CMD ["npm", "start"]
