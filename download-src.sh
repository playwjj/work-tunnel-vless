#!/bin/sh
#
# work-tunnel-vless 一键部署脚本
#
# 功能：
#   1. 自动安装依赖（git / nodejs / npm，仅支持 Alpine 自动安装）
#   2. 从 GitHub 下载 src/ 目录和 package.json
#   3. 交互式创建 .env 配置文件（已存在则跳过）
#   4. 执行 npm install 安装依赖
#   5. 注册 OpenRC 服务并启动（开机自动运行，SSH 关闭后持续运行）
#
# 兼容系统：
#   Alpine Linux 3.20+（推荐）、任意已安装 git + node + npm 的 Linux 系统
#
# 使用方法：
#
#   方式一：wget（Alpine 默认可用）
#     wget -qO /tmp/s.sh https://raw.githubusercontent.com/playwjj/work-tunnel-vless/main/download-src.sh && sh /tmp/s.sh
#
#   方式二：curl
#     curl -fsSL https://raw.githubusercontent.com/playwjj/work-tunnel-vless/main/download-src.sh -o /tmp/s.sh && sh /tmp/s.sh
#
#   方式三：本地运行
#     sh download-src.sh
#
# 环境变量说明（运行时交互输入）：
#   UUID          VLESS 用户 UUID，必填
#   TUNNEL_DOMAIN 公网域名，必填，例如 example.com
#   PORT          监听端口，可选，默认 3000
#   NAME          节点名称，可选，默认取系统 hostname
#
set -e

# ── 依赖自检（Alpine 自动安装）────────────────────────────────
check_deps() {
  MISSING=""
  for cmd in git node npm; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING="$MISSING $cmd"
  done

  if [ -n "$MISSING" ]; then
    if command -v apk >/dev/null 2>&1; then
      echo "==> Installing missing dependencies:$MISSING ..."
      apk add --no-cache git nodejs npm
    else
      echo "Error: missing dependencies:$MISSING" >&2
      echo "Please install them manually and re-run." >&2
      exit 1
    fi
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

# ── 下载文件 ─────────────────────────────────────────────────
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

# ── 创建 .env ─────────────────────────────────────────────────
if [ -f "$DEST/.env" ]; then
  echo "==> .env already exists, skipping creation."
else
  echo "==> Creating .env ..."

  printf "Enter UUID (required): "
  read -r UUID_VAL
  if [ -z "$UUID_VAL" ]; then
    echo "Error: UUID cannot be empty." >&2
    exit 1
  fi

  printf "Enter TUNNEL_DOMAIN (required, e.g. example.com): "
  read -r DOMAIN_VAL
  if [ -z "$DOMAIN_VAL" ]; then
    echo "Error: TUNNEL_DOMAIN cannot be empty." >&2
    exit 1
  fi

  printf "Enter PORT [default: 3000]: "
  read -r PORT_VAL
  PORT_VAL="${PORT_VAL:-3000}"

  printf "Enter NAME [default: hostname]: "
  read -r NAME_VAL

  cat > "$DEST/.env" << EOF
UUID=$UUID_VAL
TUNNEL_DOMAIN=$DOMAIN_VAL
PORT=$PORT_VAL
EOF

  [ -n "$NAME_VAL" ] && printf "NAME=%s\n" "$NAME_VAL" >> "$DEST/.env"

  echo "    .env created."
fi

# ── npm install ───────────────────────────────────────────────
echo "==> Running npm install ..."
cd "$DEST"
npm install

# ── OpenRC 服务 ───────────────────────────────────────────────
SERVICE_NAME="$(basename "$DEST")"
SERVICE_FILE="/etc/init.d/$SERVICE_NAME"
NODE_BIN="$(command -v node)"

echo "==> Setting up OpenRC service: $SERVICE_NAME ..."

cat > "$SERVICE_FILE" << EOF
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

chmod +x "$SERVICE_FILE"
rc-update add "$SERVICE_NAME" default
rc-service "$SERVICE_NAME" start
echo "    Service $SERVICE_NAME started and enabled on boot."
echo ""
echo "  Useful commands:"
echo "    rc-service $SERVICE_NAME status   # 查看状态"
echo "    rc-service $SERVICE_NAME stop     # 停止服务"
echo "    rc-service $SERVICE_NAME restart  # 重启服务"
echo "    tail -f /var/log/$SERVICE_NAME.log  # 查看日志"
