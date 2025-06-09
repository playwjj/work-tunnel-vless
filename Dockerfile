FROM node:18-alpine

WORKDIR /app

# 安装 cloudflared 及其依赖
RUN apk add --no-cache curl ca-certificates tzdata && \
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

COPY package*.json ./
RUN npm ci

COPY . .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# 使用 shell 脚本启动服务
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

CMD ["/app/start.sh"] 