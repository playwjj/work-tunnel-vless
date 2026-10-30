const { test } = require("node:test");
const assert = require("node:assert");
const http = require("http");
const { WebSocket } = require("ws");
const { setupWebSocketServer } = require("../src/wsHandler");

const UUID = "4b1b6efa1f0d49aeb66f2ef036c26138";
const HEARTBEAT = 100;

async function startServer() {
  const server = http.createServer();
  const wss = setupWebSocketServer(server, UUID, { heartbeatInterval: HEARTBEAT });
  await new Promise((resolve) => server.listen(0, resolve));
  const close = () => {
    for (const ws of wss.clients) ws.terminate();
    wss.close();
    server.close();
  };
  return { url: `ws://127.0.0.1:${server.address().port}`, close };
}

test("不响应 pong 的连接被心跳清理", { timeout: 2000 }, async () => {
  const { url, close } = await startServer();
  // autoPong: false 模拟已断网、不再回应 ping 的客户端
  const ws = new WebSocket(url, { autoPong: false });
  const start = Date.now();
  await new Promise((resolve) => ws.once("close", resolve));
  close();
  assert.ok(Date.now() - start < HEARTBEAT * 5);
});

test("正常响应 pong 的连接保持存活", async () => {
  const { url, close } = await startServer();
  const ws = new WebSocket(url);
  let closed = false;
  ws.once("close", () => {
    closed = true;
  });
  await new Promise((resolve) => setTimeout(resolve, HEARTBEAT * 5));
  assert.strictEqual(closed, false);
  ws.terminate();
  close();
});
