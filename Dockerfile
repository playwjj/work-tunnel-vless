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

# 以非 root 用户运行（node 镜像自带 node 用户），服务端口高于 1024 无需特权
USER node

# PORT 在运行时由环境变量注入，shell 形式才能展开
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-3000}/" || exit 1

CMD ["/app/start.sh"]
