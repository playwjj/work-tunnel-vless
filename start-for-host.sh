#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CLOUDFLARED_BIN="$SCRIPT_DIR/cloudflared"

# .env 只会被 node 里的 dotenv 加载，这里手动导出到 shell 环境，
# 这样 cloudflared 启动判断也能读到 TUNNEL_TOKEN 等变量
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

# 按架构下载 cloudflared（首次启动才下载，之后复用）
if [ ! -x "$CLOUDFLARED_BIN" ]; then
    echo "下载 cloudflared..."
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)        CF_ARCH="amd64" ;;
        aarch64|arm64) CF_ARCH="arm64" ;;
        armv7l|armv6l) CF_ARCH="arm" ;;
        *) echo "不支持的架构: $ARCH"; exit 1 ;;
    esac
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi

# 面板在执行 index.js 前已经跑过 npm install，这里无需重复

CLOUDFLARED_ARGS="--no-autoupdate"
[ "$TUNNEL_FORCE_IP_VERSION" = "6" ] && CLOUDFLARED_ARGS="$CLOUDFLARED_ARGS --edge-ip-version 6"
[ -n "$TUNNEL_TRANSPORT_PROTOCOL" ] && CLOUDFLARED_ARGS="$CLOUDFLARED_ARGS --protocol $TUNNEL_TRANSPORT_PROTOCOL"

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "警告: 未设置 TUNNEL_TOKEN，跳过 cloudflared"
else
    echo "启动 cloudflared tunnel..."
    "$CLOUDFLARED_BIN" tunnel $CLOUDFLARED_ARGS run --token "$TUNNEL_TOKEN" >/dev/null 2>&1 &
fi

# 必须前台运行，index.js 里的 exec 才能保持容器存活
exec npm run start
