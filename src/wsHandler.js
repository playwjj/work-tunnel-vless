const { WebSocketServer, createWebSocketStream } = require("ws");
const net = require("net");
const { pipeline } = require("stream");
const { parseHost, createUUIDValidator } = require("./utils/parser");
const { CONNECTION_CONFIG, RETRY_CONFIG } = require("./config");

const SUCCESS_RESPONSE = Buffer.from([0x00, 0x00]);

function setupWebSocketServer(server, uuid) {
  const wss = new WebSocketServer({ server });
  const validateUUID = createUUIDValidator(uuid);

  wss.on("connection", (ws) => {
    let connectionTimeout = setTimeout(() => {
      console.warn("[WARN] 连接超时");
      ws.close();
    }, 30000);

    ws.once("message", async (msg) => {
      clearTimeout(connectionTimeout);

      try {
        const id = msg.slice(1, 17);
        if (!validateUUID(id)) {
          console.warn("[WARN] 无效的 UUID 连接");
          ws.close();
          return;
        }

        let i = msg.readUInt8(17) + 19;
        const port = msg.readUInt16BE(i);
        i += 2;

        const { host, endIndex } = parseHost(msg, i);
        if (!host) {
          console.error("[ERROR] 无法解析目标主机");
          ws.close();
          return;
        }
        i = endIndex;

        const payload = msg.slice(i);

        ws.send(SUCCESS_RESPONSE);
        const wsStream = createWebSocketStream(ws);

        let retries = 0;

        const connect = () => {
          const socket = net.connect({ host, port, ...CONNECTION_CONFIG }, () => {
            socket.setMaxListeners(5);
            socket.write(payload);
          });

          pipeline(wsStream, socket, (err) => {
            if (err && err.code !== 'ECONNRESET' && err.code !== 'ETIMEDOUT') {
              console.error("[ERROR] WebSocket -> TCP 传输错误:", err.message);
            }
            socket.destroy();
          });

          pipeline(socket, wsStream, (err) => {
            if (err) console.error("[ERROR] TCP -> WebSocket 传输错误");
            ws.close();
          });

          socket.on("error", (err) => {
            console.error("[ERROR] TCP 连接错误");
            if (retries < RETRY_CONFIG.maxRetries) {
              retries++;
              console.log(`[INFO] 重试连接 (${retries}/${RETRY_CONFIG.maxRetries})`);
              setTimeout(connect, RETRY_CONFIG.retryDelay);
            } else {
              console.error("[ERROR] 达到最大重试次数");
              ws.close();
            }
          });

          socket.on("close", () => {
            socket.removeAllListeners();
            ws.close();
          });
        };

        connect();
      } catch (err) {
        console.error("[ERROR] WebSocket 消息处理错误");
        ws.close();
      }
    });

    ws.on("close", () => {
      clearTimeout(connectionTimeout);
    });

    ws.on("error", (err) => {
      console.error("[ERROR] WebSocket 连接错误:", err.message);
      ws.close();
    });
  });
}

module.exports = { setupWebSocketServer };


