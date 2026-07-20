require("dotenv").config();
const http = require("http");
const os = require("os");
const { getEnvVariable } = require("./config");
const { monitorMemoryUsage } = require("./utils/memory");
const { setupWebSocketServer } = require("./wsHandler");
const { isValidUUID, isValidPort, isValidDomain } = require("./utils/validators");

// Function to generate VLESS URL
function generateVlessUrl(uuid, domain, name) {
  const encodedPath = encodeURIComponent(`/work-tunnel-${name}`);
  return `vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=${encodedPath}`;
}

// Generate a Clash-compatible YAML config and return it as base64 string
function generateClashConfig(uuid, domain, name, pathPrefix = "/work-tunnel-") {
  const wsPath = `${pathPrefix}${name}`;
  const nodeName = `${domain}:443`;
  const yaml = `port: 7890
socks-port: 7891
redir-port: 0
allow-lan: false
mode: Rule
log-level: info
external-controller: :9090
proxies:
  - name: ${JSON.stringify(nodeName)}
    type: vless
    server: ${domain}
    port: 443
    uuid: ${uuid}
    udp: true
    tls: true
    network: ws
    servername: ${domain}
    skip-cert-verify: true
    ws-opts:
      path: ${JSON.stringify(wsPath)}
      headers:
        Host: ${domain}

proxy-groups:
  - name: "🔰 节点选择"
    type: select
    proxies:
      - "♻️ 自动选择"
      - "🎯 全球直连"
      - ${JSON.stringify(nodeName)}
  
  - name: "♻️ 自动选择"
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - ${JSON.stringify(nodeName)}
  
  - name: "🎯 全球直连"
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,🔰 节点选择
`;

  return yaml;
}

async function main() {
  try {
    // Start memory monitoring as early as possible
    monitorMemoryUsage();

    const UUID = getEnvVariable("UUID", isValidUUID);
    const PORT = getEnvVariable("PORT", isValidPort, "3000");
    const TUNNEL_DOMAIN = getEnvVariable("TUNNEL_DOMAIN", isValidDomain);
    const NAME = process.env.NAME || os.hostname();

    const server = http.createServer((req, res) => {
      try {
        if (req.url === "/") {
          res.writeHead(200, { "Content-Type": "text/plain" });
          res.end("Hello world!\n");
        } else if (req.url === `/clash/${UUID}`) {
          const clashCfg = generateClashConfig(UUID, TUNNEL_DOMAIN, NAME, VLESS_PATH_PREFIX);
          res.writeHead(200, { "Content-Type": "text/plain" });
          res.end(clashCfg + "\n");
        } else if (req.url === `/${UUID}`) {
          const vlessURL = generateVlessUrl(UUID, TUNNEL_DOMAIN, NAME);
          res.writeHead(200, { "Content-Type": "text/plain" });
          res.end(vlessURL + "\n");
        } else {
          res.writeHead(404, { "Content-Type": "text/plain" });
          res.end("Not Found\n");
        }
      } catch (handlerError) {
        console.error("处理 HTTP 请求时出错:", handlerError);
        res.writeHead(500, { "Content-Type": "text/plain" });
        res.end("Internal Server Error\n");
      }
    });

    server.listen(Number(PORT), () => {
      console.log(`[INFO] 服务已启动 - 端口: ${PORT}`);
    });

    setupWebSocketServer(server, UUID.replace(/-/g, ""));
  } catch (err) {
    console.error("[ERROR] 服务启动失败:", err.message);
    process.exit(1);
  }
}

// 统一处理未捕获的错误
process.on("uncaughtException", (err) => {
  console.error("[FATAL] 程序异常:", err.message);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  console.error("[FATAL] Promise 异常:", reason);
  process.exit(1);
});

main();


