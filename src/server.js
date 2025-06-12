require("dotenv").config();
const http = require("http");
const os = require("os");
const { getEnvVariable } = require("./config");
const { monitorMemoryUsage } = require("./utils/memory");
const { setupWebSocketServer } = require("./wsHandler");
const { isValidUUID, isValidPort, isValidDomain } = require("./utils/validators");

// Function to generate VLESS URL
function generateVlessUrl(uuid, domain, name, pathPrefix = "/work-tunnel-") {
  const encodedPath = encodeURIComponent(`${pathPrefix}${name}`);
  return `vless://${uuid}@${domain}:443?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=${encodedPath}`;
}

async function main() {
  try {
    // Start memory monitoring as early as possible
    monitorMemoryUsage();

    const UUID = getEnvVariable("UUID", isValidUUID);
    const PORT = getEnvVariable("PORT", isValidPort, "3000");
    const TUNNEL_DOMAIN = getEnvVariable("TUNNEL_DOMAIN", isValidDomain);
    const NAME = process.env.NAME || os.hostname();
    const VLESS_PATH_PREFIX = process.env.VLESS_PATH_PREFIX || "/work-tunnel-";

    const server = http.createServer((req, res) => {
      try {
        if (req.url === "/") {
          res.writeHead(200, { "Content-Type": "text/plain" });
          res.end("Hello world!\n");
        } else if (req.url === `/${UUID}`) {
          const vlessURL = generateVlessUrl(UUID, TUNNEL_DOMAIN, NAME, VLESS_PATH_PREFIX);
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


