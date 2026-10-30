FROM node:22-alpine

# Docker buildx 自动注入，无需手动传入
ARG TARGETARCH

WORKDIR /app

# 安装 cloudflared，根据目标架构选择对应二进制；curl 仅用于下载，用完即删
RUN apk add --no-cache ca-certificates tzdata && \
    apk add --no-cache --virtual .fetch-deps curl && \
    case "${TARGETARCH}" in \
      arm64) ARCH="arm64" ;; \
      arm)   ARCH="arm" ;; \
      *)     ARCH="amd64" ;; \
    esac && \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared \
    && apk del .fetch-deps

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY . .
RUN chmod +x /app/start.sh /app/run-cloudflared.sh

ENV NODE_ENV=production

CMD ["/app/start.sh"]
