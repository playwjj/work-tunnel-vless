#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

NODE_PID=""
CF_PID=""

stop_all() {
    kill $NODE_PID $CF_PID 2>/dev/null
    wait
}

# 收到停止信号时转发给子进程，保证 docker stop 能优雅退出
trap 'stop_all; exit 0' TERM INT

# 直接用 node 启动，避免 npm 吞掉信号
node src/server.js &
NODE_PID=$!

if [ -n "$TUNNEL_TOKEN" ]; then
    ./run-cloudflared.sh &
    CF_PID=$!
else
    echo "Warning: TUNNEL_TOKEN is not set, skipping cloudflared"
fi

# 任一进程退出即整体退出，交给容器 restart 策略重启，避免"半死"状态
while kill -0 "$NODE_PID" 2>/dev/null && { [ -z "$CF_PID" ] || kill -0 "$CF_PID" 2>/dev/null; }; do
    sleep 2 &
    wait $!
done

echo "A child process exited, shutting down"
stop_all
exit 1
