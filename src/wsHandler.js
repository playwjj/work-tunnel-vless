const { WebSocketServer, createWebSocketStream } = require('ws');
const net = require('net');
const { pipeline } = require('stream');
const { parseHost, createUUIDValidator } = require('./utils/parser');
const { CONNECTION_CONFIG, RETRY_CONFIG } = require('./config');

const SUCCESS_RESPONSE = Buffer.from([0x00, 0x00]);

function setupWebSocketServer(server, uuid) {
  const wss = new WebSocketServer({ server });
  const validateUUID = createUUIDValidator(uuid);

  wss.on('connection', (ws) => {
    const timeout = setTimeout(() => ws.close(), 30000);

    ws.once('message', (msg) => {
      try {
        const id = msg.slice(1, 17);
        if (!validateUUID(id)) {
          console.warn('无效UUID连接尝试');
          ws.close();
          return;
        }

        let i = msg.readUInt8(17) + 19;
        const port = msg.readUInt16BE(i);
        i += 2;

        const { host, endIndex } = parseHost(msg, i);
        i = endIndex;

        const payload = msg.slice(i);

        ws.send(SUCCESS_RESPONSE);
        const wsStream = createWebSocketStream(ws);

        let retry = 0;

        const connect = () => {
          const socket = net.connect({ host, port, ...CONNECTION_CONFIG }, () => {
            clearTimeout(timeout);
            socket.write(payload);

            pipeline(wsStream, socket, (err) => {
              if (err) console.error('WebSocket → TCP 错误:', err.message);
              socket.destroy();
            });

            pipeline(socket, wsStream, (err) => {
              if (err) console.error('TCP → WebSocket 错误:', err.message);
              ws.close();
            });
          });

          socket.on('error', (err) => {
            if (retry++ < RETRY_CONFIG.maxRetries) {
              console.log(`连接失败，重试 ${retry}/${RETRY_CONFIG.maxRetries}`);
              setTimeout(connect, RETRY_CONFIG.retryDelay);
            } else {
              console.error('TCP连接失败:', err.message);
              ws.close();
            }
          });

          socket.setTimeout(CONNECTION_CONFIG.timeout, () => {
            console.warn('连接超时');
            socket.destroy();
            ws.close();
          });
        };

        connect();
      } catch (err) {
        console.error('WebSocket 消息处理失败:', err.message);
        ws.close();
      }
    });

    ws.on('close', () => clearTimeout(timeout));
    ws.on('error', (err) => console.error('WebSocket 错误:', err.message));
  });
}

module.exports = { setupWebSocketServer };
