const { isValidUUID, isValidPort, isValidDomain } = require("./validators");
require("dotenv").config();

function getEnvVariable(name, validator, defaultValue = "") {
  let value = process.env[name];

  if (value) {
    if (!validator(value)) {
      console.error(`环境变量 ${name} 的值无效: ${value}`);
      process.exit(1);
    }
    return value;
  }

  if (defaultValue) {
    if (!validator(defaultValue)) {
      console.error(`默认值 ${defaultValue} 为 ${name} 无效`);
      process.exit(1);
    }
    return defaultValue;
  }

  console.error(`缺少必要的环境变量: ${name}`);
  process.exit(1);
}

module.exports = {
  getEnvVariable,
  CONNECTION_CONFIG: { timeout: 5000, family: 4, keepAlive: true, keepAliveInitialDelay: 10000, noDelay: true },
  RETRY_CONFIG: { maxRetries: 2, retryDelay: 1000 },
};


