FROM node:18-alpine

# Docker buildx 自动注入，无需手动传入
ARG TARGETARCH

WORKDIR /app

# 安装 cloudflared 及其依赖，根据目标架构选择对应二进制
RUN apk add --no-cache curl ca-certificates tzdata && \
    case "${TARGETARCH}" in \
      arm64) ARCH="arm64" ;; \
      arm)   ARCH="arm" ;; \
      *)     ARCH="amd64" ;; \
    esac && \
    curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}" \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

COPY package*.json ./
RUN npm ci

COPY . .

# 使用 shell 脚本启动服务
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

CMD ["/app/start.sh"] 