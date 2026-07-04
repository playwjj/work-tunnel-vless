const { exec } = require('child_process');

exec('sh ./start.sh', (error, stdout, stderr) => {
  if (error) {
    console.error(`执行错误: ${error}`);
    return;
  }
  console.log(`输出: ${stdout}`);
  if (stderr) {
    console.error(`错误输出: ${stderr}`);
  }
});