#!/bin/sh

# 启动 Node.js 应用
npm run start &

# 构建 cloudflared 参数
CLOUDFLARED_ARGS="--no-autoupdate"

# 如果设置了强制 IPv6，添加参数
if [ "$TUNNEL_FORCE_IP_VERSION" = "6" ]; then
    CLOUDFLARED_ARGS="$CLOUDFLARED_ARGS --edge-ip-version 6"
    echo "Using IPv6 for cloudflared"
fi

# 如果设置了传输协议
if [ ! -z "$TUNNEL_TRANSPORT_PROTOCOL" ]; then
    CLOUDFLARED_ARGS="$CLOUDFLARED_ARGS --protocol $TUNNEL_TRANSPORT_PROTOCOL"
fi

echo "Starting cloudflared with args: $CLOUDFLARED_ARGS"

# 启动 cloudflared tunnel
exec cloudflared tunnel $CLOUDFLARED_ARGS run --token $TUNNEL_TOKEN