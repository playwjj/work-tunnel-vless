#!/bin/sh
#
# work-tunnel-vless 一键部署脚本
#
# 功能：
#   1. 自动安装依赖（Alpine 用 apk，Ubuntu/Debian 用 apt）
#   2. 从 GitHub 下载 src/ 目录和 package.json
#   3. 下载 cloudflared（自动识别 CPU 架构）
#   4. 交互式创建 .env 配置文件（已存在则跳过）
#   5. 执行 npm install 安装依赖
#   6. 注册并启动系统服务（开机自启，SSH 关闭后持续运行）
#      Alpine  → OpenRC
#      Ubuntu/Debian → systemd
#
# 兼容系统：
#   Alpine Linux 3.20+、Ubuntu 20.04+、Debian 11+
#
# 使用方法：
#
#   方式一：wget
#     wget -qO /tmp/s.sh https://raw.githubusercontent.com/playwjj/work-tunnel-vless/main/install.sh && sh /tmp/s.sh
#
#   方式二：curl
#     curl -fsSL https://raw.githubusercontent.com/playwjj/work-tunnel-vless/main/install.sh -o /tmp/s.sh && sh /tmp/s.sh
#
#   方式三：本地运行
#     sh install.sh
#
# 环境变量说明（运行时交互输入）：
#   UUID          VLESS 用户 UUID，必填
#   TUNNEL_DOMAIN 公网域名，必填，例如 example.com
#   TUNNEL_TOKEN  Cloudflare Tunnel Token，必填
#   PORT          监听端口，可选，默认 3000
#   NAME          节点名称，可选，默认取系统 hostname
#
set -e

# ── 检测初始化系统 ────────────────────────────────────────────
detect_init() {
  if command -v rc-service >/dev/null 2>&1; then
    echo "openrc"
  elif command -v systemctl >/dev/null 2>&1; then
    echo "systemd"
  else
    echo "unknown"
  fi
}

INIT_SYS="$(detect_init)"

# ── 依赖自检与安装 ────────────────────────────────────────────
check_deps() {
  MISSING=""
  for cmd in git node npm; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING="$MISSING $cmd"
  done

  [ -z "$MISSING" ] && return

  echo "==> Installing missing dependencies:$MISSING ..."
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache git nodejs npm
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq git nodejs npm
  else
    echo "Error: missing dependencies:$MISSING" >&2
    echo "Please install them manually and re-run." >&2
    exit 1
  fi
}

check_deps

REPO="playwjj/work-tunnel-vless"
BRANCH="main"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ── 目标目录 ─────────────────────────────────────────────────
printf "Enter install directory [default: work-tunnel-vless]: "
read -r DIR_VAL
DEST="$(pwd)/${DIR_VAL:-work-tunnel-vless}"

if [ -d "$DEST" ]; then
  echo "==> Directory $DEST already exists, files will be updated."
else
  mkdir -p "$DEST"
  echo "==> Created directory: $DEST"
fi

# ── 下载项目文件 ──────────────────────────────────────────────
download_with_git() {
  git clone -q --depth 1 "https://github.com/$REPO.git" "$TMP_DIR/repo"
  mkdir -p "$DEST/src"
  cp -r "$TMP_DIR/repo/src/." "$DEST/src/"
  cp "$TMP_DIR/repo/package.json" "$DEST/package.json"
}

download_with_curl() {
  API="https://api.github.com/repos/$REPO/git/trees/$BRANCH?recursive=1"
  FILES=$(curl -fsSL "$API" | grep -o '"path":"src/[^"]*"' | sed 's/"path":"//;s/"//g')

  echo "$FILES" | while IFS= read -r file; do
    [ -z "$file" ] && continue
    rel="${file#src/}"
    mkdir -p "$DEST/src/$(dirname "$rel")"
    echo "  $file"
    curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/$file" -o "$DEST/$file"
  done

  echo "  package.json"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/package.json" -o "$DEST/package.json"
}

echo "==> Downloading files from $REPO ..."
if command -v git >/dev/null 2>&1; then
  download_with_git
elif command -v curl >/dev/null 2>&1; then
  download_with_curl
else
  echo "Error: git or curl is required." >&2
  exit 1
fi
echo "    src/ and package.json downloaded."

# ── 下载 cloudflared ──────────────────────────────────────────
CF_BIN="/usr/local/bin/cloudflared"

if [ -f "$CF_BIN" ]; then
  echo "==> cloudflared already exists, skipping download."
else
  echo "==> Downloading cloudflared ..."
  case "$(uname -m)" in
    x86_64)  CF_ARCH="amd64" ;;
    aarch64) CF_ARCH="arm64" ;;
    armv7l)  CF_ARCH="arm" ;;
    *) echo "Error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$CF_URL" -o "$CF_BIN"
  else
    wget -qO "$CF_BIN" "$CF_URL"
  fi
  chmod +x "$CF_BIN"
  echo "    cloudflared downloaded to $CF_BIN"
fi

# ── 创建 .env ─────────────────────────────────────────────────
if [ -f "$DEST/.env" ]; then
  echo "==> .env already exists, skipping creation."
else
  echo "==> Creating .env ..."

  printf "Enter UUID (required): "
  read -r UUID_VAL
  if [ -z "$UUID_VAL" ]; then
    echo "Error: UUID cannot be empty." >&2; exit 1
  fi

  printf "Enter TUNNEL_DOMAIN (required, e.g. example.com): "
  read -r DOMAIN_VAL
  if [ -z "$DOMAIN_VAL" ]; then
    echo "Error: TUNNEL_DOMAIN cannot be empty." >&2; exit 1
  fi

  printf "Enter TUNNEL_TOKEN (required): "
  read -r TOKEN_VAL
  if [ -z "$TOKEN_VAL" ]; then
    echo "Error: TUNNEL_TOKEN cannot be empty." >&2; exit 1
  fi

  printf "Enter PORT [default: 3000]: "
  read -r PORT_VAL
  PORT_VAL="${PORT_VAL:-3000}"

  printf "Enter NAME [default: hostname]: "
  read -r NAME_VAL

  cat > "$DEST/.env" << EOF
UUID=$UUID_VAL
TUNNEL_DOMAIN=$DOMAIN_VAL
TUNNEL_TOKEN=$TOKEN_VAL
PORT=$PORT_VAL
EOF

  [ -n "$NAME_VAL" ] && printf "NAME=%s\n" "$NAME_VAL" >> "$DEST/.env"
  echo "    .env created."
fi

# ── npm install ───────────────────────────────────────────────
echo "==> Running npm install ..."
cd "$DEST"
npm install

# ── 服务注册 ──────────────────────────────────────────────────
SERVICE_NAME="$(basename "$DEST")"
NODE_BIN="$(command -v node)"

setup_openrc() {
  # Node.js 服务
  cat > "/etc/init.d/$SERVICE_NAME" << EOF
#!/sbin/openrc-run

name="$SERVICE_NAME"
description="work-tunnel-vless VLESS tunnel service"
command="$NODE_BIN"
command_args="src/server.js"
directory="$DEST"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.log"

depend() {
    need net
}
EOF
  chmod +x "/etc/init.d/$SERVICE_NAME"
  rc-update add "$SERVICE_NAME" default 2>/dev/null || true
  rc-service "$SERVICE_NAME" restart

  # cloudflared 启动脚本（从 .env 读取 TOKEN）
  cat > "$DEST/start-cloudflared.sh" << EOF
#!/bin/sh
. "$DEST/.env"
exec $CF_BIN tunnel --no-autoupdate run --token "\$TUNNEL_TOKEN"
EOF
  chmod +x "$DEST/start-cloudflared.sh"

  # cloudflared 服务
  cat > "/etc/init.d/cloudflared" << EOF
#!/sbin/openrc-run

name="cloudflared"
description="Cloudflare Tunnel"
command="$DEST/start-cloudflared.sh"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/\${RC_SVCNAME}.log"
error_log="/var/log/\${RC_SVCNAME}.log"

depend() {
    need net
    after $SERVICE_NAME
}
EOF
  chmod +x "/etc/init.d/cloudflared"
  rc-update add cloudflared default 2>/dev/null || true
  rc-service cloudflared restart
}

setup_systemd() {
  # Node.js 服务
  cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=work-tunnel-vless VLESS tunnel service
After=network.target

[Service]
WorkingDirectory=$DEST
ExecStart=$NODE_BIN src/server.js
EnvironmentFile=$DEST/.env
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # cloudflared 服务
  cat > "/etc/systemd/system/cloudflared.service" << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target $SERVICE_NAME.service

[Service]
EnvironmentFile=$DEST/.env
ExecStart=$CF_BIN tunnel --no-autoupdate run --token \${TUNNEL_TOKEN}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" cloudflared
  systemctl restart "$SERVICE_NAME"
  systemctl restart cloudflared
}

echo "==> Setting up services (init: $INIT_SYS) ..."
case "$INIT_SYS" in
  openrc)  setup_openrc ;;
  systemd) setup_systemd ;;
  *)
    echo "Warning: unknown init system, skipping service setup." >&2
    echo "Please start manually: cd $DEST && node src/server.js"
    ;;
esac

# ── 完成 ──────────────────────────────────────────────────────
echo ""
echo "=============================="
echo "  Deploy complete!"
echo "=============================="

if [ "$INIT_SYS" = "systemd" ]; then
  echo "  Useful commands:"
  echo "    systemctl status $SERVICE_NAME     # Node 应用状态"
  echo "    systemctl status cloudflared        # Cloudflare 隧道状态"
  echo "    systemctl restart $SERVICE_NAME    # 重启 Node 应用"
  echo "    systemctl restart cloudflared       # 重启 Cloudflare 隧道"
  echo "    journalctl -fu $SERVICE_NAME       # Node 应用日志"
  echo "    journalctl -fu cloudflared          # Cloudflare 隧道日志"
else
  echo "  Useful commands:"
  echo "    rc-service $SERVICE_NAME status    # Node 应用状态"
  echo "    rc-service cloudflared status       # Cloudflare 隧道状态"
  echo "    rc-service $SERVICE_NAME restart   # 重启 Node 应用"
  echo "    rc-service cloudflared restart      # 重启 Cloudflare 隧道"
  echo "    tail -f /var/log/$SERVICE_NAME.log # Node 应用日志"
  echo "    tail -f /var/log/cloudflared.log    # Cloudflare 隧道日志"
fi
