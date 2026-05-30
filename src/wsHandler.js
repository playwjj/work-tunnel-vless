const { WebSocketServer, createWebSocketStream } = require("ws");
const net = require("net");
const { pipeline } = require("stream");
const { parseHost, createUUIDValidator } = require("./utils/parser");
const { CONNECTION_CONFIG } = require("./config");

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

        const socket = net.connect({ host, port, ...CONNECTION_CONFIG }, () => {
          socket.write(payload);
        });
        socket.setMaxListeners(5);

        pipeline(wsStream, socket, (err) => {
          if (err && err.code !== 'ECONNRESET' && err.code !== 'ETIMEDOUT') {
            console.error("[ERROR] WebSocket -> TCP 传输错误:", err.message);
          }
          socket.destroy();
        });

        pipeline(socket, wsStream, (err) => {
          if (err && err.code !== 'ECONNRESET' && err.code !== 'ETIMEDOUT') {
            console.error("[ERROR] TCP -> WebSocket 传输错误:", err.message);
          }
          ws.close();
        });

        socket.on("error", (err) => {
          console.error("[ERROR] TCP 连接错误:", err.message);
          ws.close();
        });
      } catch (err) {
        console.error("[ERROR] WebSocket 消息处理错误:", err.message);
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


