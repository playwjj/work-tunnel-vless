const os = require('os');
const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const { exec, execSync } = require('child_process');
const { WebSocket, createWebSocketStream } = require('ws');
const dns = require('dns');
require('dotenv').config();

// 设置DNS解析选项，优先使用IPv4
dns.setDefaultResultOrder('ipv4first');

// 设置最大内存使用限制
const MAX_MEMORY_USAGE = 512 * 1024 * 1024; // 512MB

// 定期检查内存使用
setInterval(() => {
  const used = process.memoryUsage();
  if (used.heapUsed > MAX_MEMORY_USAGE) {
    console.error('内存使用超过限制，准备重启服务');
    process.exit(1);
  }
}, 60000); // 每分钟检查一次

// 设置进程最大内存限制
process.setMaxListeners(0); // 移除监听器限制

// 读取 package.json 获取版本号
const packageJson = require('./package.json');
const VERSION = packageJson.version;

// 预分配常用Buffer
const VERSION_BUFFER = Buffer.from([0]);
const SUCCESS_RESPONSE = Buffer.from([0, 0]);

// 缓存常用对象
const textDecoder = new TextDecoder();
const emptyBuffer = Buffer.alloc(0);

// 优化UUID验证
function createUUIDValidator(uuid) {
  const uuidBytes = Buffer.from(uuid.replace(/-/g, ''), 'hex');
  return (id) => {
    return id.equals(uuidBytes);
  };
}

// 优化主机地址解析
function parseHost(msg, startIndex) {
  const ATYP = msg[startIndex];
  let host, endIndex;
  
  switch(ATYP) {
    case 1: // IPv4
      host = msg.slice(startIndex + 1, startIndex + 5).join('.');
      endIndex = startIndex + 5;
      break;
    case 2: // Domain
      const domainLength = msg[startIndex + 1];
      host = textDecoder.decode(msg.slice(startIndex + 2, startIndex + 2 + domainLength));
      endIndex = startIndex + 2 + domainLength;
      break;
    case 3: // IPv6
      const ipv6Bytes = msg.slice(startIndex + 1, startIndex + 17);
      host = ipv6Bytes.reduce((acc, byte, i) => {
        if (i % 2 === 0) {
          acc.push(byte.toString(16).padStart(2, '0') + 
                  ipv6Bytes[i + 1].toString(16).padStart(2, '0'));
        }
        return acc;
      }, []).join(':');
      endIndex = startIndex + 17;
      break;
    default:
      throw new Error('Invalid address type');
  }
  
  return { host, endIndex };
}

// 检查并安装必要的模块
function ensureModule(name) {
  try {
    require.resolve(name);
  } catch (e) {
    console.log(`正在安装模块 '${name}'...`);
    execSync(`npm install ${name}`, { stdio: 'inherit' });
  }
}

// 确保ws模块已安装
ensureModule('ws');
console.log(`启动 work tunnel vless v${VERSION}`);

const NAME = process.env.NAME || os.hostname();

// 验证端口号是否有效
function isValidPort(port) {
  const portNum = parseInt(port);
  return !isNaN(portNum) && portNum > 0 && portNum < 65536;
}

// 验证UUID格式
function isValidUUID(uuid) {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(uuid);
}

// 验证域名格式
function isValidDomain(domain) {
  const domainRegex = /^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/;
  return domainRegex.test(domain);
}

async function getEnvVariable(variableName, defaultValue, required = false) {
  const envValue = process.env[variableName];
  if (envValue) {
    if (variableName === 'PORT' && !isValidPort(envValue)) {
      console.error(`环境变量 ${variableName} 的值 ${envValue} 不是有效的端口号`);
      process.exit(1);
    }
    if (variableName === 'UUID' && !isValidUUID(envValue)) {
      console.error(`环境变量 ${variableName} 的值不是有效的UUID格式`);
      process.exit(1);
    }
    if (variableName === 'TUNNEL_DOMAIN' && !isValidDomain(envValue)) {
      console.error(`环境变量 ${variableName} 的值不是有效的域名格式`);
      process.exit(1);
    }
    return envValue;
  }
  
  if (defaultValue) return defaultValue;
  if (!required) return '';
  
  let input = '';
  while (!input) {
    input = await ask(`请输入${variableName}: `);
    if (!input) {
      console.log(`${variableName}不能为空，请重新输入!`);
      continue;
    }
    
    // 验证输入值
    if (variableName === 'PORT' && !isValidPort(input)) {
      console.log('请输入有效的端口号(1-65535)');
      input = '';
    } else if (variableName === 'UUID' && !isValidUUID(input)) {
      console.log('请输入有效的UUID格式');
      input = '';
    } else if (variableName === 'TUNNEL_DOMAIN' && !isValidDomain(input)) {
      console.log('请输入有效的域名格式');
      input = '';
    }
  }
  return input;
}

function ask(question) {
  const rl = require('readline').createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => rl.question(question, ans => { rl.close(); resolve(ans.trim()); }));
}

async function main() {
  try {
    const UUID = await getEnvVariable('UUID', '', true);
    console.log('UUID:', UUID);

    const PORT = await getEnvVariable('PORT', '3000', true);
    console.log('端口:', PORT);

    const TUNNEL_DOMAIN = await getEnvVariable('TUNNEL_DOMAIN', '', true);
    console.log('域名:', TUNNEL_DOMAIN);

    const httpServer = http.createServer((req, res) => {
      try {
        if (req.url === '/') {
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end('Hello, World!\n');
        } else if (req.url === `/${UUID}`) {
          const vlessURL = `vless://${UUID}@${TUNNEL_DOMAIN}:443?encryption=none&security=tls&sni=${TUNNEL_DOMAIN}&fp=chrome&type=ws&host=${TUNNEL_DOMAIN}&path=%2F#work-tunnel-${NAME}`;
          res.writeHead(200, { 'Content-Type': 'text/plain' });
          res.end(vlessURL + '\n');
        } else {
          res.writeHead(404, { 'Content-Type': 'text/plain' });
          res.end('Not Found\n');
        }
      } catch (error) {
        console.error('HTTP请求处理错误:', error);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Internal Server Error\n');
      }
    });

    httpServer.listen(Number(PORT), () => {
      console.log(`HTTP服务器运行在端口 ${PORT}`);
    });

    const wss = new WebSocket.Server({ server: httpServer });
    const uuid = UUID.replace(/-/g, "");

    wss.on('connection', ws => {
      const connectionTimeout = setTimeout(() => {
        ws.close();
      }, 30000);

      ws.once('message', msg => {
        try {
          const [VERSION] = msg;
          const id = msg.slice(1, 17);
          
          // 使用缓存的验证器
          const validateUUID = createUUIDValidator(uuid);
          if (!validateUUID(id)) {
            console.log('UUID验证失败');
            ws.close();
            return;
          }

          let i = msg.slice(17, 18).readUInt8() + 19;
          const port = msg.slice(i, i += 2).readUInt16BE(0);
          
          // 使用优化的主机解析
          const { host, endIndex } = parseHost(msg, i);
          i = endIndex;

          // 使用预分配的Buffer
          ws.send(SUCCESS_RESPONSE);
          const duplex = createWebSocketStream(ws);
          
          let retryCount = 0;
          const tryConnect = () => {
            const connection = net.connect({ 
              host, 
              port,
              timeout: 5000,        // 降低超时时间到5秒
              family: 4,           // 强制使用IPv4
              keepAlive: true,     // 启用keepalive
              keepAliveInitialDelay: 10000,  // 10秒后开始keepalive
              noDelay: true        // 禁用Nagle算法
            }, function () {
              clearTimeout(connectionTimeout);
              this.write(msg.slice(i));
              
              // 优化流处理
              duplex.on('error', (err) => {
                console.error('WebSocket流错误:', err);
              }).pipe(this, { 
                end: false,
                highWaterMark: 64 * 1024 // 64KB buffer
              }).on('error', (err) => {
                console.error('TCP连接错误:', err);
              }).pipe(duplex, {
                end: false,
                highWaterMark: 64 * 1024
              });
            });

            connection.on('error', (err) => {
              // 忽略IPv6相关错误
              if (err.code === 'ENETUNREACH' && err.address && err.address.includes(':')) {
                return;
              }
              
              // 处理连接错误
              if (retryCount < RETRY_CONFIG.maxRetries) {
                retryCount++;
                console.log(`连接失败，第${retryCount}次重试...`);
                setTimeout(tryConnect, RETRY_CONFIG.retryDelay);
              } else {
                console.error('TCP连接错误:', err);
                ws.close();
              }
            });

            connection.on('timeout', () => {
              connection.destroy();
              if (retryCount < RETRY_CONFIG.maxRetries) {
                retryCount++;
                console.log(`连接超时，第${retryCount}次重试...`);
                setTimeout(tryConnect, RETRY_CONFIG.retryDelay);
              } else {
                console.error('TCP连接超时');
                ws.close();
              }
            });

            // 添加连接成功事件处理
            connection.on('connect', () => {
              console.log(`成功连接到 ${host}:${port}`);
            });
          };

          // 开始连接尝试
          tryConnect();

        } catch (error) {
          console.error('WebSocket消息处理错误:', error);
          ws.close();
        }
      });

      ws.on('error', (error) => {
        console.error('WebSocket错误:', error);
      });

      ws.on('close', () => {
        clearTimeout(connectionTimeout);
      });
    });

  } catch (error) {
    console.error('程序运行错误:', error);
    process.exit(1);
  }
}

// 处理未捕获的异常
process.on('uncaughtException', (error) => {
  console.error('未捕获的异常:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('未处理的Promise拒绝:', reason);
});

main();