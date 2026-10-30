#!/bin/sh
#
# 统一的 cloudflared 启动入口，start.sh、start-for-host.sh 及 install.sh
# 注册的系统服务都通过它启动，参数拼接逻辑只维护这一份。
#
# 用法：run-cloudflared.sh [cloudflared 可执行文件路径，默认取 PATH 中的 cloudflared]
#
# 读取的环境变量：
#   TUNNEL_TOKEN               Cloudflare Tunnel Token，必填
#   TUNNEL_FORCE_IP_VERSION    设为 6 时强制使用 IPv6 连接边缘节点
#   TUNNEL_TRANSPORT_PROTOCOL  传输协议，如 quic、http2
#
set -e

CLOUDFLARED_BIN="${1:-cloudflared}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 宿主机部署时环境变量写在同目录的 .env 中（容器内没有该文件，变量由 Docker 注入）。
# 与 node 端 dotenv 行为一致：已设置的环境变量优先，.env 只补充缺失的值
if [ -f "$SCRIPT_DIR/.env" ]; then
    _token="$TUNNEL_TOKEN"
    _ip_version="$TUNNEL_FORCE_IP_VERSION"
    _protocol="$TUNNEL_TRANSPORT_PROTOCOL"
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/.env"
    TUNNEL_TOKEN="${_token:-$TUNNEL_TOKEN}"
    TUNNEL_FORCE_IP_VERSION="${_ip_version:-$TUNNEL_FORCE_IP_VERSION}"
    TUNNEL_TRANSPORT_PROTOCOL="${_protocol:-$TUNNEL_TRANSPORT_PROTOCOL}"
fi

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "Error: TUNNEL_TOKEN is not set" >&2
    exit 1
fi

set -- --no-autoupdate

if [ "$TUNNEL_FORCE_IP_VERSION" = "6" ]; then
    set -- "$@" --edge-ip-version 6
    echo "Using IPv6 for cloudflared"
fi

if [ -n "$TUNNEL_TRANSPORT_PROTOCOL" ]; then
    set -- "$@" --protocol "$TUNNEL_TRANSPORT_PROTOCOL"
fi

echo "Starting cloudflared with args: $*"
exec "$CLOUDFLARED_BIN" tunnel "$@" run --token "$TUNNEL_TOKEN"
