const { test, before, after } = require("node:test");
const assert = require("node:assert");
const net = require("net");
const path = require("path");
const { spawn } = require("child_process");
const { WebSocket } = require("ws");

const UUID = "4b1b6efa-1f0d-49ae-b66f-2ef036c26138";
const DOMAIN = "tunnel.example.com";

let server;
let echo;
let serverPort;
let echoPort;

function freePort() {
  return new Promise((resolve) => {
    const srv = net.createServer().listen(0, () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

// 构造 VLESS 请求头：版本 + UUID + 附加信息长度 + 命令(TCP) + 端口 + IPv4 地址
function vlessHeader(uuid, port, payload) {
  const head = Buffer.alloc(1 + 16 + 1 + 1 + 2 + 1 + 4);
  Buffer.from(uuid.replace(/-/g, ""), "hex").copy(head, 1);
  head[18] = 1;
  head.writeUInt16BE(port, 19);
  head[21] = 1;
  Buffer.from([127, 0, 0, 1]).copy(head, 22);
  return Buffer.concat([head, payload]);
}

before(async () => {
  serverPort = await freePort();
  echo = net.createServer((s) => s.pipe(s));
  await new Promise((resolve) => echo.listen(0, resolve));
  echoPort = echo.address().port;

  server = spawn(process.execPath, [path.join(__dirname, "../src/server.js")], {
    env: { ...process.env, UUID, TUNNEL_DOMAIN: DOMAIN, PORT: String(serverPort), NAME: "ci" },
    stdio: ["ignore", "pipe", "inherit"],
  });
  await new Promise((resolve, reject) => {
    server.stdout.on("data", (d) => d.toString().includes("服务已启动") && resolve());
    server.once("exit", (code) => reject(new Error(`server exited: ${code}`)));
  });
});

after(() => {
  server?.kill();
  echo?.close();
});

test("HTTP 根路径返回 Hello world", async () => {
  const res = await fetch(`http://127.0.0.1:${serverPort}/`);
  assert.strictEqual(res.status, 200);
  assert.strictEqual(await res.text(), "Hello world!\n");
});

test("/UUID 返回 VLESS 链接", async () => {
  const res = await fetch(`http://127.0.0.1:${serverPort}/${UUID}`);
  const body = await res.text();
  assert.ok(body.startsWith(`vless://${UUID}@${DOMAIN}:443?`));
  assert.ok(body.includes("path=%2Fwork-tunnel-ci"));
});

test("未知路径返回 404", async () => {
  const res = await fetch(`http://127.0.0.1:${serverPort}/nope`);
  assert.strictEqual(res.status, 404);
});

test("VLESS 转发保持数据顺序", async () => {
  const ws = new WebSocket(`ws://127.0.0.1:${serverPort}`);
  await new Promise((resolve) => ws.once("open", resolve));

  let received = Buffer.alloc(0);
  let handshake = false;
  const done = new Promise((resolve) => {
    ws.on("message", (m) => {
      if (!handshake) {
        handshake = true;
        assert.deepStrictEqual(m, Buffer.from([0, 0]));
        return;
      }
      received = Buffer.concat([received, m]);
      if (received.length >= 3) resolve();
    });
  });

  ws.send(vlessHeader(UUID, echoPort, Buffer.from("A")));
  ws.send(Buffer.from("B"));
  ws.send(Buffer.from("C"));
  await done;
  ws.close();
  assert.strictEqual(received.toString(), "ABC");
});

test("错误的 UUID 被拒绝", async () => {
  const ws = new WebSocket(`ws://127.0.0.1:${serverPort}`);
  await new Promise((resolve) => ws.once("open", resolve));
  const closed = new Promise((resolve) => ws.once("close", resolve));
  ws.send(vlessHeader("00000000-0000-0000-0000-000000000000", echoPort, Buffer.from("A")));
  await closed;
});
