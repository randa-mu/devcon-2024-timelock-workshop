ARG ARCH=linux/amd64
ARG REGISTRY=europe-west1-docker.pkg.dev
ARG NODE_VERSION=22.3

FROM --platform=${ARCH} ${REGISTRY}/randamu-prod/candyland/node:${NODE_VERSION} AS builder
WORKDIR /app

# we want to leverage docker layer caching
COPY package.json /app/
RUN npm install

COPY . /app/
RUN npm run build

FROM --platform=${ARCH} ${REGISTRY}/randamu-prod/candyland/node:${NODE_VERSION}
COPY --from=builder /app/dist/index.js index.js
ENTRYPOINT node /index.js
