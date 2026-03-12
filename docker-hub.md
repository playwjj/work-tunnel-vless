# passport888/work-tunnel-vless

## 基于 Node.js 的 VLESS + Cloudflare Tunnel 代理服务器

本项目提供一个基于 Node.js 的 Docker 化 VLESS 代理服务器，无缝集成 Cloudflare Tunnel，旨在为开发者提供一个安全、高效且易于部署的一键式代理解决方案。

### ✨ 特性

*   **支持 VLESS 协议**: 实现现代、安全的代理连接。
*   **自动验证配置**: 自动检查 UUID、端口和域名格式，减少配置错误。
*   **环境变量配置**: 所有配置通过环境变量管理，灵活方便。
*   **WebSocket 支持**: 提供 WebSocket 连接选项，增强兼容性和隐蔽性。
*   **自动依赖安装**: Docker 镜像构建过程自动处理所有依赖。
*   **集成 Cloudflare Tunnel**: 利用 Cloudflare 的全球网络，无需公网 IP 即可暴露服务。
*   **简便部署**: 支持 Docker run 和 Docker Compose 方式部署。
*   **多架构支持**: 同时提供 `linux/amd64` 和 `linux/arm64` 镜像，适配 x86 服务器及 ARM 设备（树莓派、Apple Silicon 等）。

### 🏗️ 支持架构

| 架构 | 标签 |
|------|------|
| `linux/amd64` | `latest`, `x.x.x` |
| `linux/arm64` | `latest`, `x.x.x` |

### 📋 技术要求

*   Node.js (版本 >= 14)
*   npm
*   Docker (可选)
*   Docker Compose (推荐)

### 🎯 适用人群

*   需要快速搭建代理服务的开发者。
*   注重网络隐私和安全的用户。
*   Cloudflare 生态的用户。

### 🚀 使用方法

#### 1. 获取 Cloudflare Tunnel Token

访问 [Cloudflare Zero Trust 控制台](https://dash.cloudflare.com/) 创建一个新的 Tunnel，并复制生成的 Tunnel Token。

**配置 Public Hostname:**

在 Tunnel 详情页面，点击 "Configure"，选择 "Public Hostname" 标签，然后点击 "Add a public hostname"。输入你的域名（例如：`tunnel.yourdomain.com`），选择 "HTTP" 服务类型，并在 URL 中输入 `http://127.0.0.1:[PORT]`（这里的 `[PORT]` 是你在 `.env` 文件中配置的服务监听端口）。

#### 2. 配置环境变量

创建一个 `.env` 文件，填入以下必要的环境变量：

```dotenv
UUID=你的 UUID
PORT=服务监听端口 (例如: 8080)
TUNNEL_DOMAIN=你的域名 (例如: tunnel.yourdomain.com)
TUNNEL_TOKEN=你的 Cloudflare Tunnel Token
```

可选环境变量：

```dotenv
NAME=服务器名称 (默认为主机名)
TUNNEL_FORCE_IP_VERSION=强制使用指定 IP 版本 (设为 6 时强制使用 IPv6)
TUNNEL_TRANSPORT_PROTOCOL=cloudflared 传输协议 (如 quic、http2 等)
```

#### 3. 使用 Docker 启动服务

**方法一：使用 Docker run**

```bash
docker run -d \
  --name work-tunnel-vless \
  --env-file .env \
  passport888/work-tunnel-vless:latest
```

**方法二：使用 Docker Compose (推荐)**

创建一个 `docker-compose.yml` 文件：

```yaml
version: '3'
services:
  work-tunnel-vless:
    image: passport888/work-tunnel-vless:latest
    container_name: work-tunnel-vless
    env_file:
      - .env
    restart: unless-stopped
```

然后运行：

```bash
docker-compose up -d
```

### 🌐 访问服务

服务启动成功后，你可以通过以下 VLESS 链接访问：

通过以下URL获取 https://[TUNNEL_DOMAIN]/[UUID]

请将 `UUID`, `TUNNEL_DOMAIN` 替换为你自己的配置。

**重要提示：**

*   建议使用 HTTPS 和 WSS (WebSocket Secure) 协议以提高安全性。
*   请妥善保管你的 UUID，避免泄露。

### 📄 许可证

本项目采用 [MIT License](https://github.com/playwjj/work-tunnel-vless/blob/main/LICENSE) 开源。

### 👋 贡献

欢迎提交 Issue 和 Pull Request！

### 🔗 项目地址

GitHub: [https://github.com/playwjj/work-tunnel-vless](https://github.com/playwjj/work-tunnel-vless)  
Docker Hub: [https://hub.docker.com/r/passport888/work-tunnel-vless](https://hub.docker.com/r/passport888/work-tunnel-vless)  


