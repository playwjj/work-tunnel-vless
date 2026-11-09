#!/bin/sh
#
# work-tunnel-vless 一键部署脚本
#
# 功能：
#   1. 自动安装依赖（Alpine 用 apk，Ubuntu/Debian 用 apt）
#   2. 从 GitHub 下载最新正式版本的 src/ 目录、package.json 和 run-cloudflared.sh
#   3. 下载 cloudflared（自动识别 CPU 架构）
#   4. 交互式创建 .env 配置文件（已存在则跳过）
#   5. 执行 npm install 安装依赖
#   6. 注册并启动系统服务（开机自启，SSH 关闭后持续运行）
#      Alpine  → OpenRC
#      Ubuntu/Debian → systemd
#      supervisord 容器（如 Uppcoder 等 PaaS）→ supervisor.d 程序配置
#
# 兼容系统：
#   Alpine Linux 3.20+、Ubuntu 20.04+、Debian 11+、
#   以 supervisord 为 1 号进程的容器环境
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
#   默认安装最新正式版本，可通过 VERSION 环境变量指定：
#     VERSION=v1.2.9 sh /tmp/s.sh   # 安装指定版本
#     VERSION=main sh /tmp/s.sh     # 安装 main 分支开发版
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
  elif [ "$(cat /proc/1/comm 2>/dev/null)" = "supervisord" ] || \
       { command -v supervisorctl >/dev/null 2>&1 && [ -d "$HOME/.config/supervisor.d" ]; }; then
    # PaaS 容器（如 Uppcoder）：没有 systemd/OpenRC，1 号进程就是 supervisord
    echo "supervisord"
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

# ── 确定安装版本 ──────────────────────────────────────────────
# 默认取最新正式版本（GitHub Release），与 Docker 镜像的 latest 保持一致
resolve_latest_version() {
  if command -v curl >/dev/null 2>&1; then
    # releases/latest 会重定向到 .../releases/tag/vX.Y.Z，无需调用有频率限制的 API
    curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" \
      | sed -n 's|.*/releases/tag/||p'
  else
    git ls-remote --tags --refs --sort=-v:refname "https://github.com/$REPO.git" 'v*' \
      | head -n 1 | sed 's|.*refs/tags/||'
  fi
}

if [ -z "$VERSION" ]; then
  VERSION="$(resolve_latest_version)"
  if [ -z "$VERSION" ]; then
    echo "Error: could not determine the latest release version." >&2
    echo "Set it explicitly, e.g. VERSION=v1.2.10 sh $0" >&2
    exit 1
  fi
fi

# ── 下载项目文件 ──────────────────────────────────────────────
version_not_found() {
  echo "Error: version $VERSION not found in $REPO." >&2
  echo "See https://github.com/$REPO/releases for available versions." >&2
  exit 1
}

download_with_git() {
  git clone -q --depth 1 --branch "$VERSION" "https://github.com/$REPO.git" "$TMP_DIR/repo" 2>/dev/null \
    || version_not_found
}

download_with_curl() {
  case "$VERSION" in
    v*) REF="tags/$VERSION" ;;
    *)  REF="heads/$VERSION" ;;
  esac
  curl -fsSL "https://github.com/$REPO/archive/refs/$REF.tar.gz" -o "$TMP_DIR/source.tar.gz" \
    || version_not_found
  mkdir -p "$TMP_DIR/archive"
  tar -xzf "$TMP_DIR/source.tar.gz" -C "$TMP_DIR/archive"
  # 源码包内只有一个顶层目录（如 work-tunnel-vless-1.2.10）
  mv "$TMP_DIR/archive/"* "$TMP_DIR/repo"
}

echo "==> Downloading $REPO $VERSION ..."
if command -v git >/dev/null 2>&1; then
  download_with_git
elif command -v curl >/dev/null 2>&1; then
  download_with_curl
else
  echo "Error: git or curl is required." >&2
  exit 1
fi

# run-cloudflared.sh 自 v1.2.9 起提供，本脚本注册的服务依赖它
if [ ! -f "$TMP_DIR/repo/run-cloudflared.sh" ]; then
  echo "Error: $VERSION is too old for this installer, please use v1.2.9 or later." >&2
  exit 1
fi

mkdir -p "$DEST/src"
cp -r "$TMP_DIR/repo/src/." "$DEST/src/"
cp "$TMP_DIR/repo/package.json" "$DEST/package.json"
cp "$TMP_DIR/repo/run-cloudflared.sh" "$DEST/run-cloudflared.sh"
chmod +x "$DEST/run-cloudflared.sh"
echo "    src/, package.json and run-cloudflared.sh ($VERSION) installed."

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
npm install --omit=dev

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

  # 旧版本生成的启动脚本，已由 run-cloudflared.sh 取代
  rm -f "$DEST/start-cloudflared.sh"

  # cloudflared 服务（run-cloudflared.sh 自行读取同目录的 .env）
  cat > "/etc/init.d/cloudflared" << EOF
#!/sbin/openrc-run

name="cloudflared"
description="Cloudflare Tunnel"
command="$DEST/run-cloudflared.sh"
command_args="$CF_BIN"
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
ExecStart=$DEST/run-cloudflared.sh $CF_BIN
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

# supervisord 容器（如 Uppcoder 等 PaaS）：1 号进程是 supervisord，平台自身
# 的服务（nginx、sshd 等）都由它管理。把两个程序按「一个程序一个文件」
# 写进用户级 supervisor.d，由 supervisord 在启动时加载；部分平台只在栈
# （重新）启动时扫描该目录，写完需在面板里 Restart 一次栈才生效。
setup_supervisord() {
  # 程序配置目录：只认平台已经存在的目录，自己新建的目录 supervisord
  # 不一定会读，写了也白写
  SUP_D=""
  for d in "$HOME/.config/supervisor.d" "/etc/supervisor/conf.d" "$HOME/.config/supervisor/conf.d"; do
    if [ -d "$d" ]; then SUP_D="$d"; break; fi
  done
  if [ -z "$SUP_D" ]; then
    echo "Warning: supervisord detected but no supervisor.d/conf.d directory found, skipping." >&2
    echo "Please start manually: cd $DEST && node src/server.js"
    return
  fi

  # 日志目录：root 用 /var/log；普通用户用 ~/log（托管平台惯例，
  # 且 /var/log 对普通用户通常不可写）
  if [ "$IS_ROOT" = "1" ]; then LOG_DIR="/var/log"; else LOG_DIR="$HOME/log"; fi
  mkdir -p "$LOG_DIR"

  cat > "$SUP_D/$SERVICE_NAME.conf" << EOF
[program:$SERVICE_NAME]
command=$NODE_BIN src/server.js
directory=$DEST
autostart=true
autorestart=true
stdout_logfile=$LOG_DIR/$SERVICE_NAME.log
redirect_stderr=true
EOF

  # cloudflared 服务（run-cloudflared.sh 自行读取同目录的 .env）
  cat > "$SUP_D/cloudflared.conf" << EOF
[program:cloudflared]
command=$DEST/run-cloudflared.sh $CF_BIN
directory=$DEST
autostart=true
autorestart=true
stdout_logfile=$LOG_DIR/cloudflared.log
redirect_stderr=true
EOF
  echo "    supervisor program files written to $SUP_D"

  # 主配置文件位置各平台不同，supervisorctl 默认找不到时必须显式 -c
  SUP_CONF=""
  for f in "$HOME/.config/supervisord.conf" "/etc/supervisor/supervisord.conf" "/etc/supervisord.conf"; do
    if [ -f "$f" ]; then SUP_CONF="$f"; break; fi
  done
  SUP_CTL="supervisorctl"
  [ -n "$SUP_CONF" ] && SUP_CTL="supervisorctl -c $SUP_CONF"

  # 尝试让正在运行的 supervisord 立即加载（其主配置 include 了该目录时
  # 直接生效）；守护进程不接受也不算失败，按平台规则重启后自会加载。
  if command -v supervisorctl >/dev/null 2>&1 && $SUP_CTL reread >/dev/null 2>&1; then
    $SUP_CTL update >/dev/null 2>&1 || true
    echo "    supervisord reloaded; check status with: $SUP_CTL status"
  else
    echo "Note: supervisord will pick up the new programs at its next start." >&2
    echo "      On panel platforms (e.g. Uppcoder), restart the stack once to activate." >&2
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
  supervisord) setup_supervisord ;;
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
elif [ "$INIT_SYS" = "supervisord" ]; then
  echo "  Useful commands:"
  echo "    ${SUP_CTL:-supervisorctl} status    # 全部程序状态"
  echo "    ${SUP_CTL:-supervisorctl} restart $SERVICE_NAME    # 重启 Node 应用"
  echo "    ${SUP_CTL:-supervisorctl} restart cloudflared       # 重启 Cloudflare 隧道"
  echo "    tail -f ${LOG_DIR:-$HOME/log}/$SERVICE_NAME.log # Node 应用日志"
  echo "    tail -f ${LOG_DIR:-$HOME/log}/cloudflared.log    # Cloudflare 隧道日志"
else
  echo "  Useful commands:"
  echo "    rc-service $SERVICE_NAME status    # Node 应用状态"
  echo "    rc-service cloudflared status       # Cloudflare 隧道状态"
  echo "    rc-service $SERVICE_NAME restart   # 重启 Node 应用"
  echo "    rc-service cloudflared restart      # 重启 Cloudflare 隧道"
  echo "    tail -f /var/log/$SERVICE_NAME.log # Node 应用日志"
  echo "    tail -f /var/log/cloudflared.log    # Cloudflare 隧道日志"
fi
