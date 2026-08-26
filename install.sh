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

# ── root 权限检测 ──────────────────────────────────────────────
# 非 root 用户无法写 /etc/systemd/system 等系统目录（常见于共享/托管环境，
# 如 DomCloud 等只提供普通用户 SSH 的托管平台）。此时 systemd 场景下改用
# 用户级服务（systemctl --user），无需任何系统权限。
IS_ROOT=0
[ "$(id -u)" = "0" ] && IS_ROOT=1

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
    apt-get install -y -qq git curl
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sh -
    apt-get install -y -qq nodejs
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
# 安装到 $DEST/bin/ 而不是 /usr/local/bin/，避免普通用户没有写系统目录的权限
CF_BIN="$DEST/bin/cloudflared"
mkdir -p "$DEST/bin"

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

  # 日志轮转兜底：output_log/error_log 不会自动轮转，长期运行会把日志写到
  # 磁盘写满（尤其是小磁盘的容器/面板环境）。用 crond 的 hourly 周期任务
  # 兜底截断，避免占满磁盘导致 DNS/服务异常。
  if [ -d /etc/periodic/hourly ]; then
    LOG_GUARD="/etc/periodic/hourly/${SERVICE_NAME}-logguard"
    cat > "$LOG_GUARD" << EOF
#!/bin/sh
for f in "/var/log/${SERVICE_NAME}.log" "/var/log/cloudflared.log"; do
  [ -f "\$f" ] || continue
  size=\$(wc -c < "\$f" 2>/dev/null || echo 0)
  if [ "\$size" -gt 5242880 ]; then
    mv -f "\$f" "\$f.old"
    : > "\$f"
  fi
done
EOF
    chmod +x "$LOG_GUARD"
  fi
}

setup_systemd() {
  if [ "$IS_ROOT" = "1" ]; then
    UNIT_DIR="/etc/systemd/system"
    SYSTEMCTL="systemctl"
  else
    # 非 root：装到用户级 systemd（无需系统权限）
    UNIT_DIR="$HOME/.config/systemd/user"
    SYSTEMCTL="systemctl --user"
    mkdir -p "$UNIT_DIR"
  fi

  # Node.js 服务
  cat > "$UNIT_DIR/$SERVICE_NAME.service" << EOF
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
LogRateLimitIntervalSec=30
LogRateLimitBurst=200

[Install]
WantedBy=$([ "$IS_ROOT" = "1" ] && echo multi-user.target || echo default.target)
EOF

  # cloudflared 服务
  cat > "$UNIT_DIR/cloudflared.service" << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target $SERVICE_NAME.service

[Service]
EnvironmentFile=$DEST/.env
ExecStart=$CF_BIN tunnel --no-autoupdate run --token \$TUNNEL_TOKEN
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
LogRateLimitIntervalSec=30
LogRateLimitBurst=200

[Install]
WantedBy=$([ "$IS_ROOT" = "1" ] && echo multi-user.target || echo default.target)
EOF

  $SYSTEMCTL daemon-reload
  $SYSTEMCTL enable "$SERVICE_NAME" cloudflared
  $SYSTEMCTL restart "$SERVICE_NAME"
  $SYSTEMCTL restart cloudflared

  if [ "$IS_ROOT" != "1" ]; then
    # 让用户级服务在 SSH 断开后继续运行；无 sudo 权限时会静默失败，
    # 此时需要托管平台本身支持保活（如 DomCloud），或手动联系管理员开启。
    if command -v loginctl >/dev/null 2>&1; then
      loginctl enable-linger "$(whoami)" 2>/dev/null || \
        echo "Note: could not enable lingering (needs root). If services stop after SSH disconnect, ask your host to run: loginctl enable-linger $(whoami)" >&2
    fi
  fi
}

echo "==> Setting up services (init: $INIT_SYS, root: $IS_ROOT) ..."
case "$INIT_SYS" in
  openrc)
    if [ "$IS_ROOT" != "1" ]; then
      echo "Warning: OpenRC service setup requires root, skipping." >&2
      echo "Please start manually: cd $DEST && node src/server.js"
    else
      setup_openrc
    fi
    ;;
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
  if [ "$IS_ROOT" = "1" ]; then
    SC="systemctl"; JC="journalctl"
  else
    SC="systemctl --user"; JC="journalctl --user"
    echo "  (installed as user-level systemd service, no root required)"
  fi
  echo "  Useful commands:"
  echo "    $SC status $SERVICE_NAME     # Node 应用状态"
  echo "    $SC status cloudflared        # Cloudflare 隧道状态"
  echo "    $SC restart $SERVICE_NAME    # 重启 Node 应用"
  echo "    $SC restart cloudflared       # 重启 Cloudflare 隧道"
  echo "    $JC -fu $SERVICE_NAME       # Node 应用日志"
  echo "    $JC -fu cloudflared          # Cloudflare 隧道日志"
else
  echo "  Useful commands:"
  echo "    rc-service $SERVICE_NAME status    # Node 应用状态"
  echo "    rc-service cloudflared status       # Cloudflare 隧道状态"
  echo "    rc-service $SERVICE_NAME restart   # 重启 Node 应用"
  echo "    rc-service cloudflared restart      # 重启 Cloudflare 隧道"
  echo "    tail -f /var/log/$SERVICE_NAME.log # Node 应用日志"
  echo "    tail -f /var/log/cloudflared.log    # Cloudflare 隧道日志"
fi
