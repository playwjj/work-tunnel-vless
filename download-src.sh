#!/bin/sh
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
  git -C "$TMP_DIR" init -q
  git -C "$TMP_DIR" remote add origin "https://github.com/$REPO.git"
  git -C "$TMP_DIR" sparse-checkout init --cone
  git -C "$TMP_DIR" sparse-checkout set src
  git -C "$TMP_DIR" pull -q origin "$BRANCH"
  mkdir -p "$DEST/src"
  cp -r "$TMP_DIR/src/." "$DEST/src/"
  cp "$TMP_DIR/package.json" "$DEST/package.json"
  cp "$TMP_DIR/index.js" "$DEST/index.js"
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
  echo "  index.js"
  curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/index.js" -o "$DEST/index.js"
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
echo "    src/, index.js and package.json downloaded."

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

# ── npm run start ─────────────────────────────────────────────
echo "==> Starting application ..."
npm run start
