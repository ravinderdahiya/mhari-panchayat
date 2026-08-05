module.exports = {
  apps: [
    {
      name: "mhari-panchayat-backend",
      script: "../tools/php84/php.exe",
      args: ["artisan", "serve", "--host=127.0.0.1", "--port=8083"],
      interpreter: "none",
      cwd: "D:/EODB_HARSAC/mhari-panchayat/backend",
      exec_mode: "fork",
      instances: 1,
      watch: false,
      autorestart: true,
      max_restarts: 15,
      min_uptime: "10s",
      restart_delay: 5000,
      max_memory_restart: "512M",
      kill_timeout: 8000,
      error_file: "./logs/pm2-error.log",
      out_file: "./logs/pm2-out.log",
      merge_logs: true,
      time: true
    }
  ]
};
