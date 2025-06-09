#!/bin/sh

# 启动 Node.js 应用
npm run start &

# 启动 cloudflared tunnel
exec cloudflared tunnel --no-autoupdate run --token $TUNNEL_TOKEN 