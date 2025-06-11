const readline = require('readline');
const { isValidUUID, isValidPort, isValidDomain } = require('./utils/validators');
require('dotenv').config();

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => rl.question(question, ans => {
    rl.close();
    resolve(ans.trim());
  }));
}

async function getEnvVariable(name, defaultValue = '', required = false) {
  const value = process.env[name];

  if (value) {
    if (name === 'UUID' && !isValidUUID(value)) {
      console.error(`UUID 格式无效: ${value}`);
      process.exit(1);
    }
    if (name === 'PORT' && !isValidPort(value)) {
      console.error(`PORT 无效: ${value}`);
      process.exit(1);
    }
    if (name === 'TUNNEL_DOMAIN' && !isValidDomain(value)) {
      console.error(`TUNNEL_DOMAIN 无效: ${value}`);
      process.exit(1);
    }
    return value;
  }

  if (!required) return defaultValue;

  let input = '';
  while (!input) {
    input = await ask(`请输入 ${name}: `);
    if (name === 'UUID' && !isValidUUID(input)) {
      console.log('无效 UUID 格式');
      input = '';
    } else if (name === 'PORT' && !isValidPort(input)) {
      console.log('无效端口号 (1-65535)');
      input = '';
    } else if (name === 'TUNNEL_DOMAIN' && !isValidDomain(input)) {
      console.log('无效域名格式');
      input = '';
    }
  }

  return input;
}

module.exports = {
  getEnvVariable,
  CONNECTION_CONFIG: { timeout: 5000, family: 4, keepAlive: true, keepAliveInitialDelay: 10000, noDelay: true },
  RETRY_CONFIG: { maxRetries: 2, retryDelay: 1000 }
};
