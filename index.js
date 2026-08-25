const { spawn } = require('child_process');

const child = spawn('sh', ['./start.sh'], { stdio: 'inherit' });

child.on('exit', (code, signal) => {
  process.exit(code !== null ? code : 1);
});

const forwardSignal = (signal) => {
  child.kill(signal);
};

process.on('SIGTERM', forwardSignal);
process.on('SIGINT', forwardSignal);
