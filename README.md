# Work Tunnel VLESS

一个基于 Node.js 的 VLESS 代理服务器。

## 功能特点

- 支持 VLESS 协议
- 自动验证 UUID、端口和域名格式
- 支持环境变量配置
- 提供 WebSocket 连接
- 自动安装依赖

## 系统要求

- Node.js >= 14
- npm

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
- 主页：`http://[域名]:[端口]/`
- VLESS 链接：`http://[域名]:[端口]/[UUID]`

## 注意事项

- 确保服务器防火墙已开放相应端口
- 建议使用 HTTPS 和 WSS 协议
- 请妥善保管 UUID，不要泄露给他人

## 许可证

MIT 