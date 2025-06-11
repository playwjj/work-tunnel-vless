const MAX_MEMORY_USAGE = 512 * 1024 * 1024; // 512MB

function monitorMemoryUsage(interval = 60000) {
  setInterval(() => {
    const used = process.memoryUsage();
    if (used.heapUsed > MAX_MEMORY_USAGE) {
      console.error('内存使用超过限制，准备重启服务');
      process.exit(1);
    }
  }, interval);
}

module.exports = {
  monitorMemoryUsage,
};
