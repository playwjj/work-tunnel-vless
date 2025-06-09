const os = require('os');
const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const { exec, execSync } = require('child_process');
const { WebSocket, createWebSocketStream } = require('ws');
require('dotenv').config();

// 读取 package.json 获取版本号
const packageJson = require('./package.json');
const VERSION = packageJson.version;

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
          res.end('Hello, World-YGkkk\n');
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
      //console.log('新的WebSocket连接已建立');
      
      ws.once('message', msg => {
        try {
          const [VERSION] = msg;
          const id = msg.slice(1, 17);
          
          if (!id.every((v, i) => v == parseInt(uuid.substr(i * 2, 2), 16))) {
            console.log('UUID验证失败');
            ws.close();
            return;
          }

          let i = msg.slice(17, 18).readUInt8() + 19;
          const port = msg.slice(i, i += 2).readUInt16BE(0);
          const ATYP = msg.slice(i, i += 1).readUInt8();
          
          let host;
          try {
            host = ATYP == 1 ? msg.slice(i, i += 4).join('.') :
              (ATYP == 2 ? new TextDecoder().decode(msg.slice(i + 1, i += 1 + msg.slice(i, i + 1).readUInt8())) :
                (ATYP == 3 ? msg.slice(i, i += 16).reduce((s, b, i, a) => (i % 2 ? s.concat(a.slice(i - 1, i + 1)) : s), []).map(b => b.readUInt16BE(0).toString(16)).join(':') : ''));
          } catch (error) {
            console.error('解析主机地址失败:', error);
            ws.close();
            return;
          }

          ws.send(new Uint8Array([VERSION, 0]));
          const duplex = createWebSocketStream(ws);
          
          const connection = net.connect({ host, port }, function () {
            this.write(msg.slice(i));
            duplex.on('error', (err) => {
              console.error('WebSocket流错误:', err);
            }).pipe(this).on('error', (err) => {
              console.error('TCP连接错误:', err);
            }).pipe(duplex);
          });

          connection.on('error', (err) => {
            console.error('TCP连接错误:', err);
            ws.close();
          });

        } catch (error) {
          console.error('WebSocket消息处理错误:', error);
          ws.close();
        }
      });

      ws.on('error', (error) => {
        console.error('WebSocket错误:', error);
      });

      ws.on('close', () => {
        //console.log('WebSocket连接已关闭');
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