require("dotenv").config();

function getEnvVariable(name, validator, defaultValue = "") {
  let value = process.env[name];
  
  if (value) {
    if (!validator(value)) {
      throw new Error(`环境变量 ${name} 的值无效: ${value}`);
    }
    return value;
  }
  
  if (defaultValue) {
    if (!validator(defaultValue)) {
      throw new Error(`默认值 ${defaultValue} 为 ${name} 无效`);
    }
    return defaultValue;
  }
  
  throw new Error(`缺少必要的环境变量: ${name}`);
}

module.exports = {
  getEnvVariable,
  CONNECTION_CONFIG: { timeout: 5000, family: 4, keepAlive: true, keepAliveInitialDelay: 10000, noDelay: true },
  RETRY_CONFIG: { maxRetries: 2, retryDelay: 1000 },
};


