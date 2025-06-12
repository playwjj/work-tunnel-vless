# Work Tunnel VLESS

一个基于 Node.js 的 Docker 化 VLESS 代理服务器，集成 Cloudflare Tunnel，为开发者提供安全、高效的一键式代理解决方案。  

## 功能特点

- 支持 VLESS 协议
- 自动验证 UUID、端口和域名格式
- 支持环境变量配置
- 提供 WebSocket 连接
- 自动安装依赖

## 应用场景

- 固定 IP 访问：通过配置固定的服务器 IP 访问特定网站，数据经由安全隧道传输，提供额外的安全保障，解除网站IP限制。
- 远程办公：为远程工作的团队成员提供安全的网络访问通道，确保数据传输的安全性
- 跨区域访问：解决因地理位置限制导致的访问问题，提供稳定的网络连接
- 开发测试：为开发人员提供安全的测试环境，方便进行跨区域的应用测试
- 数据同步：确保跨区域数据同步过程中的传输安全，防止数据泄露
- 企业内网访问：为企业员工提供安全的远程访问内网资源的解决方案

## 系统要求

- Node.js >= 14
- npm

## Cloudflare Zero Trust Tunnel 配置

1. 登录 Cloudflare Zero Trust 控制台
   - 访问 https://dash.cloudflare.com/
   - 选择 "Zero Trust" 选项

2. 创建 Tunnel
   - 在左侧菜单选择 "Access" -> "Tunnels"
   - 点击 "Create a tunnel"
   - 输入隧道名称（例如：`work-tunnel-vless`）
   - 选择 "Docker" 作为环境
   - 复制生成的 Tunnel Token

3. 配置 Public Hostname
   - 在 Tunnel 详情页面，点击 "Configure"
   - 选择 "Public Hostname" 标签
   - 点击 "Add a public hostname"
   - 输入你的域名（例如：`tunnel.yourdomain.com`）
   - 选择 "HTTP" 服务类型
   - 在 URL 中输入 `http://localhost:8080`（或你的 VLESS 服务端口）

4. 获取必要的配置信息
   - Tunnel Token：用于认证
   - 域名：用于访问服务

## 安装步骤

1. 克隆仓库：
```bash
git clone https://github.com/playwjj/work-tunnel-vless.git
cd work-tunnel-vless
```

2. 安装依赖：
```bash
npm install
```

3. 配置环境变量：
```bash
cp .env.sample .env
```
然后编辑 `.env` 文件，填入必要的配置信息。

### 使用 Docker 运行

1. 直接使用 Docker Hub 镜像：
```bash
docker run -d \
  --name work-tunnel-vless \
  --env-file .env \
  passport888/work-tunnel-vless:latest
```

2. 或者从源码构建镜像：
```bash
docker build -t work-tunnel-vless .
docker run -d \
  --name work-tunnel-vless \
  --env-file .env \
  work-tunnel-vless
```

### 使用 Docker Compose

1. 创建 `docker-compose.yml` 文件：
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

2. 启动服务：
```bash
docker-compose up -d
```

## 配置说明

必需的环境变量：
- `UUID`: VLESS 协议的 UUID
- `PORT`: 服务器监听端口
- `TUNNEL_DOMAIN`: 服务器域名
- `TUNNEL_TOKEN`: Cloudflare Tunnel 的认证令牌

可选的环境变量：
- `NAME`: 服务器名称（默认为主机名）

## 使用方法

1. 启动服务器：
```bash
npm start
```

2. 访问以下地址获取 VLESS 链接：
- VLESS 链接：`https://[TUNNEL_DOMAIN]/[UUID]`

## 注意事项

- 确保服务器防火墙已开放相应端口
- 建议使用 HTTPS 和 WSS 协议
- 请妥善保管 UUID，不要泄露给他人

## 许可证

MIT 