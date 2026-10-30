const { WebSocketServer, createWebSocketStream } = require("ws");
const net = require("net");
const { parseHost, createUUIDValidator } = require("./utils/parser");
const { CONNECTION_CONFIG } = require("./config");

const SUCCESS_RESPONSE = Buffer.from([0x00, 0x00]);
const HEARTBEAT_INTERVAL = 30000;

function setupWebSocketServer(server, uuid, { heartbeatInterval = HEARTBEAT_INTERVAL } = {}) {
  const wss = new WebSocketServer({ server });
  const validateUUID = createUUIDValidator(uuid);

  // 定期 ping，客户端断网后收不到 close，靠心跳发现并清理死连接
  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      ws.ping();
    }
  }, heartbeatInterval);
  wss.on("close", () => clearInterval(heartbeat));

  wss.on("connection", (ws) => {
    ws.isAlive = true;
    ws.on("pong", () => {
      ws.isAlive = true;
    });

    let connectionTimeout = setTimeout(() => {
      console.warn("[WARN] 连接超时");
      ws.close();
    }, 30000);

    ws.once("message", (msg) => {
      clearTimeout(connectionTimeout);

      try {
        const id = msg.subarray(1, 17);
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

        const payload = msg.subarray(i);

        ws.send(SUCCESS_RESPONSE);
        const wsStream = createWebSocketStream(ws);

        const socket = net.connect({ host, port, ...CONNECTION_CONFIG });
        // 首包必须先于后续 WebSocket 数据写入，连接建立前写入会按顺序缓冲
        if (payload.length) socket.write(payload);

        // timeout 仅作为建连超时，连上后取消，避免空闲长连接被误判
        socket.once("connect", () => socket.setTimeout(0));
        socket.once("timeout", () => socket.destroy(new Error(`连接 ${host}:${port} 超时`)));

        let closed = false;
        const cleanup = () => {
          if (closed) return;
          closed = true;
          wsStream.destroy();
          socket.destroy();
        };

        wsStream.pipe(socket);
        socket.pipe(wsStream);

        socket.once("error", (err) => {
          console.error("[ERROR] TCP 连接错误:", err.message);
          cleanup();
        });
        wsStream.once("error", (err) => {
          console.error("[ERROR] WebSocket 传输错误:", err.message);
          cleanup();
        });
        socket.once("close", cleanup);
        wsStream.once("close", cleanup);
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

  return wss;
}

module.exports = { setupWebSocketServer };


