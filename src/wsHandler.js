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
      console.warn("连接超时，关闭连接");
      ws.close();
    }, 30000);

    ws.once("message", async (msg) => {
      clearTimeout(connectionTimeout);

      try {
        const id = msg.slice(1, 17);
        if (!validateUUID(id)) {
          console.warn("无效 UUID 连接尝试");
          ws.close();
          return;
        }

        let i = msg.readUInt8(17) + 19;
        const port = msg.readUInt16BE(i);
        i += 2;

        const { host, endIndex } = parseHost(msg, i);
        if (!host) {
          console.error("无法解析目标主机");
          ws.close();
          return;
        }
        i = endIndex;

        const payload = msg.slice(i);

        ws.send(SUCCESS_RESPONSE);
        const wsStream = createWebSocketStream(ws);

        let retries = 0;

        const connect = () => {
          const socket = net.connect( { host, port, ...CONNECTION_CONFIG }, () => {
            socket.write(payload);
          });

          pipeline(wsStream, socket, (err) => {
            if (err) console.error("WebSocket -> TCP 错误:", err.message);
            socket.destroy();
          });

          pipeline(socket, wsStream, (err) => {
            if (err) console.error("TCP -> WebSocket 错误:", err.message);
            ws.close();
          });

          socket.on("error", (err) => {
            console.error("TCP 连接错误:", err.message);
            if (retries < RETRY_CONFIG.maxRetries) {
              retries++;
              console.log(`连接失败，尝试重试 ${retries}/${RETRY_CONFIG.maxRetries} 次...`);
              setTimeout(connect, RETRY_CONFIG.retryDelay);
            } else {
              console.error("达到最大重试次数，关闭连接");
              ws.close();
            }
          });

          socket.on("close", () => {
            console.log("TCP 连接关闭");
            ws.close();
          });
        };

        connect();
      } catch (err) {
        console.error("处理 WebSocket 消息时出错:", err);
        ws.close();
      }
    });

    ws.on("close", () => {
      clearTimeout(connectionTimeout);
      console.log("WebSocket 连接关闭");
    });

    ws.on("error", (err) => {
      console.error("WebSocket 错误:", err);
      ws.close();
    });
  });
}

module.exports = { setupWebSocketServer };


