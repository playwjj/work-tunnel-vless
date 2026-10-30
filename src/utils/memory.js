const os = require("os");

const DEFAULT_MAX_MEMORY_USAGE = 512 * 1024 * 1024; // 512MB

function monitorMemoryUsage(interval = 60000) {
  const configured = parseInt(process.env.MAX_MEMORY_USAGE, 10);
  const maxMemory = configured > 0 ? configured : DEFAULT_MAX_MEMORY_USAGE;

  setInterval(() => {
    const used = process.memoryUsage();
    if (used.heapUsed > maxMemory) {
      console.error(`[FATAL] 内存使用超限: ${(used.heapUsed / (1024 * 1024)).toFixed(2)}MB / ${(maxMemory / (1024 * 1024)).toFixed(2)}MB`);
      process.exit(1);
    }
  }, interval);
}

module.exports = {
  monitorMemoryUsage,
};


