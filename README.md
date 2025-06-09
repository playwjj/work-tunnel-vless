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
git clone [仓库地址]
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

## 配置说明

必需的环境变量：
- `UUID`: VLESS 协议的 UUID
- `PORT`: 服务器监听端口
- `DOMAIN`: 服务器域名

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