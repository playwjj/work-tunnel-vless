require('dotenv').config();
const http = require('http');
const os = require('os');
const { getEnvVariable } = require('./config');
const { monitorMemoryUsage } = require('./utils/memory');
const { setupWebSocketServer } = require('./wsHandler');

async function main() {
  const UUID = await getEnvVariable('UUID', '', true);
  const PORT = await getEnvVariable('PORT', '3000', true);
  const TUNNEL_DOMAIN = await getEnvVariable('TUNNEL_DOMAIN', '', true);
  const NAME = process.env.NAME || os.hostname();

  monitorMemoryUsage();

  const server = http.createServer((req, res) => {
    if (req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('Hello, World!\n');
    } else if (req.url === `/${UUID}`) {
      const vlessURL = `vless://${UUID}@${TUNNEL_DOMAIN}:443?encryption=none&security=tls&sni=${TUNNEL_DOMAIN}&fp=chrome&type=ws&host=${TUNNEL_DOMAIN}&path=%2F#work-tunnel-${NAME}`;
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(vlessURL + '\n');
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found\n');
    }
  });

  server.listen(Number(PORT), () => {
    console.log(`Server is running on port ${PORT}`);
  });

  setupWebSocketServer(server, UUID.replace(/-/g, ''));
}

process.on('uncaughtException', err => {
  console.error('未捕获异常:', err);
});

process.on('unhandledRejection', reason => {
  console.error('未处理的 Promise 拒绝:', reason);
});

main();
