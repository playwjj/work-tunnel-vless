// 通过真实的 Cloudflare Tunnel 做端到端检查：HTTP 路由 + VLESS 代理转发。
// 用法：node scripts/e2e-tunnel.js <域名> <UUID>
const { WebSocket } = require("ws");

const [domain, uuid] = process.argv.slice(2);
if (!domain || !uuid) {
  console.error("用法: node scripts/e2e-tunnel.js <域名> <UUID>");
  process.exit(2);
}

const TARGET_HOST = "example.com";
const TARGET_PORT = 80;
const DEADLINE = Date.now() + 90000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// 隧道刚注册时边缘节点可能短暂返回 502/530，重试直到成功或超时
async function retry(name, fn) {
  let lastError;
  while (Date.now() < DEADLINE) {
    try {
      await fn();
      console.log(`[OK] ${name}`);
      return;
    } catch (err) {
      lastError = err;
      await sleep(3000);
    }
  }
  throw new Error(`${name} 失败: ${lastError?.message}`);
}

async function checkHttp() {
  const res = await fetch(`https://${domain}/`);
  const body = await res.text();
  if (res.status !== 200 || body !== "Hello world!\n") {
    throw new Error(`/ 返回 ${res.status}: ${body.slice(0, 80)}`);
  }
}

async function checkVlessLink() {
  const res = await fetch(`https://${domain}/${uuid}`);
  const body = await res.text();
  if (res.status !== 200 || !body.startsWith(`vless://${uuid}@${domain}:443?`)) {
    throw new Error(`/UUID 返回 ${res.status}`);
  }
}

// VLESS 请求头：版本 + UUID + 附加信息长度 + 命令(TCP) + 端口 + 域名地址
function vlessRequest(payload) {
  const host = Buffer.from(TARGET_HOST);
  const head = Buffer.alloc(1 + 16 + 1 + 1 + 2 + 1 + 1);
  Buffer.from(uuid.replace(/-/g, ""), "hex").copy(head, 1);
  head[18] = 1;
  head.writeUInt16BE(TARGET_PORT, 19);
  head[21] = 2;
  head[22] = host.length;
  return Buffer.concat([head, host, payload]);
}

function checkVlessProxy() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`wss://${domain}/`);
    const timer = setTimeout(() => {
      ws.terminate();
      reject(new Error("代理请求超时"));
    }, 15000);
    let handshake = false;
    let response = "";

    ws.once("open", () => {
      const request = `HEAD / HTTP/1.1\r\nHost: ${TARGET_HOST}\r\nConnection: close\r\n\r\n`;
      ws.send(vlessRequest(Buffer.from(request)));
    });
    ws.on("message", (data) => {
      if (!handshake) {
        handshake = true;
        data = data.subarray(2);
      }
      response += data.toString();
      if (response.includes("\r\n")) {
        clearTimeout(timer);
        ws.close();
        if (/^HTTP\/1\.[01] \d{3}/.test(response)) resolve();
        else reject(new Error(`代理返回异常: ${response.slice(0, 80)}`));
      }
    });
    ws.once("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    // 已成功时 reject 不生效；未成功就被关闭（如 UUID 被拒）则立即失败
    ws.once("close", () => {
      clearTimeout(timer);
      reject(new Error("连接在收到响应前被关闭"));
    });
  });
}

async function main() {
  await retry("HTTP 根路径", checkHttp);
  await retry("VLESS 链接", checkVlessLink);
  await retry(`VLESS 代理访问 ${TARGET_HOST}:${TARGET_PORT}`, checkVlessProxy);
}

main().catch((err) => {
  console.error(`[FAIL] ${err.message}`);
  process.exit(1);
});
