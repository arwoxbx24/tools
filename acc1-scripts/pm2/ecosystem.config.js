// Единственный источник правды по pm2. Закон владельца 10.09.2026: ручной pm2 start запрещён, dump.pm2 — производный кэш.
const fs = require('fs');

function loadEnvFile(filePath) {
  const env = {};
  try {
    const lines = fs.readFileSync(filePath, 'utf8').split('\n');
    lines.forEach(line => {
      line = line.trim();
      if (line && !line.startsWith('#') && line.includes('=')) {
        const idx = line.indexOf('=');
        env[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
    });
  } catch (e) {}
  return env;
}
const pm2ApiEnv = loadEnvFile('/root/workspaces/secrets/services/pm2-api.env');

module.exports = {
  apps: [
    {
      name: 'action-log-indexer',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/action-log-indexer.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/action-log-indexer-error.log',
      out_file: '/root/.pm2/logs/action-log-indexer-out.log'
    },
    {
      name: 'amc-mvp-api',
      script: '/root/workspaces/projects/appsmith-margin-cockpit-mvp-api/server.py',
      cwd: '/root/workspaces/projects/appsmith-margin-cockpit-mvp-api',
      interpreter: 'python3',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/amc-mvp-api-error.log',
      out_file: '/root/.pm2/logs/amc-mvp-api-out.log'
    },
    {
      name: 'arwox-landing-hub',
      script: '/root/workspaces/projects/arwox-landing/hub/server.cjs',
      cwd: '/root/workspaces/projects',
      interpreter: '/root/.nvm/versions/node/v20.19.4/bin/node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/arwox-landing-hub-error.log',
      out_file: '/root/.pm2/logs/arwox-landing-hub-out.log'
    },
    {
      name: 'auto-commit',
      script: '/root/workspaces/tools/acc1-scripts/auto-commit-daemon.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/auto-commit-error.log',
      out_file: '/root/.pm2/logs/auto-commit-out.log'
    },
    {
      name: 'backup-rotation',
      script: '/root/workspaces/tools/acc1-scripts/backup-rotation.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 */6 * * *',
      error_file: '/root/.pm2/logs/backup-rotation-error.log',
      out_file: '/root/.pm2/logs/backup-rotation-out.log'
    },
    {
      name: 'backup-watcher',
      script: '/root/workspaces/tools/acc1-scripts/backup-watcher.sh',
      cwd: '/root',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/backup-watcher-error.log',
      out_file: '/root/.pm2/logs/backup-watcher-out.log'
    },
    {
      name: 'bitrix-sdk-php-server',
      script: '/usr/bin/php',
      args: [
        '-S',
        '0.0.0.0:20080',
        '-t',
        'public'
      ],
      cwd: '/root/workspaces/projects/bitrix/sdk-php',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/bitrix-sdk-php-server-error.log',
      out_file: '/root/.pm2/logs/bitrix-sdk-php-server-out.log'
    },
    {
      name: 'bitrix-sdk-updater',
      script: '/root/workspaces/tools/acc1-scripts/pm2/jobs/bitrix-sdk-updater.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 3 * * 1',
      error_file: '/root/.pm2/logs/bitrix-sdk-updater-error.log',
      out_file: '/root/.pm2/logs/bitrix-sdk-updater-out.log'
    },
    {
      name: 'bmc-api',
      script: '/root/.nvm/versions/node/v20.19.4/bin/npm',
      args: [
        'run',
        'api'
      ],
      cwd: '/root/workspaces/projects/bitrix-margin-cockpit',
      interpreter: '/root/.nvm/versions/node/v20.19.4/bin/node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/bmc-api-error.log',
      out_file: '/root/.pm2/logs/bmc-api-out.log'
    },
    {
      name: 'bmc-ui',
      script: '/root/.nvm/versions/node/v20.19.4/bin/npm',
      args: [
        'run',
        'dev'
      ],
      cwd: '/root/workspaces/projects/bitrix-margin-cockpit',
      interpreter: '/root/.nvm/versions/node/v20.19.4/bin/node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/bmc-ui-error.log',
      out_file: '/root/.pm2/logs/bmc-ui-out.log'
    },
    {
      name: 'context-gc',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/context-gc-once.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '8,38 * * * *',
      error_file: '/root/.pm2/logs/context-gc-error.log',
      out_file: '/root/.pm2/logs/context-gc-out.log'
    },
    {
      name: 'context-heartbeat',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/context-heartbeat.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '3,18,33,48 * * * *',
      error_file: '/root/.pm2/logs/context-heartbeat-error.log',
      out_file: '/root/.pm2/logs/context-heartbeat-out.log'
    },
    {
      name: 'db-replicator',
      script: '/root/workspaces/projects/transcription-dev/admin/db-replicator.js',
      cwd: '/root/workspaces/projects/transcription-dev',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/db-replicator-error.log',
      out_file: '/root/.pm2/logs/db-replicator-out.log'
    },
    {
      name: 'docker-backup',
      script: '/root/workspaces/tools/acc1-scripts/docker-backup.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 */6 * * *',
      error_file: '/root/.pm2/logs/docker-backup-error.log',
      out_file: '/root/.pm2/logs/docker-backup-out.log'
    },
    {
      name: 'docker-log-rotation',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/docker-log-rotation.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/docker-log-rotation-error.log',
      out_file: '/root/.pm2/logs/docker-log-rotation-out.log'
    },
    {
      name: 'file-cleanup',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/file-cleanup-daemon.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/file-cleanup-error.log',
      out_file: '/root/.pm2/logs/file-cleanup-out.log'
    },
    {
      name: 'gdrive-token-check',
      script: '/root/workspaces/tools/acc1-scripts/gdrive-token-check.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 */12 * * *',
      error_file: '/root/.pm2/logs/gdrive-token-check-error.log',
      out_file: '/root/.pm2/logs/gdrive-token-check-out.log'
    },
    {
      name: 'git-maintenance',
      script: '/root/workspaces/tools/acc1-scripts/git-maintenance-once.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '13 */2 * * *',
      error_file: '/root/.pm2/logs/git-maintenance-error.log',
      out_file: '/root/.pm2/logs/git-maintenance-out.log'
    },
    {
      name: 'google-token-refresh',
      script: '/root/workspaces/tools/acc1-scripts/google-token-refresh.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 3 */5 * *',
      error_file: '/root/.pm2/logs/google-token-refresh-error.log',
      out_file: '/root/.pm2/logs/google-token-refresh-out.log'
    },
    {
      name: 'gpt-codex',
      script: '/root/workspaces/projects/yubikey-v1/server/index.js',
      cwd: '/root/workspaces/projects/yubikey-v1',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/gpt-codex-error.log',
      out_file: '/root/.pm2/logs/gpt-codex-out.log'
    },
    {
      name: 'hh-booking-watch',
      script: '/root/workspaces/projects/hh-scoring/.venv/bin/python',
      args: [
        'scripts/booking_watch.py'
      ],
      cwd: '/root/workspaces/projects/hh-scoring',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-booking-watch-error.log',
      out_file: '/root/.pm2/logs/hh-booking-watch-out.log'
    },
    {
      name: 'hh-cabinet',
      script: '/root/workspaces/projects/hh-scoring/services/cabinet.py',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: '.venv/bin/python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-cabinet-error.log',
      out_file: '/root/.pm2/logs/hh-cabinet-out.log'
    },
    {
      name: 'hh-cabinet-bridge',
      script: '/usr/bin/bash',
      args: [
        '-c',
        'socat TCP-LISTEN:20099,bind=172.17.0.1,fork,reuseaddr TCP:127.0.0.1:20098'
      ],
      cwd: '/root/workspaces/projects',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-cabinet-bridge-error.log',
      out_file: '/root/.pm2/logs/hh-cabinet-bridge-out.log'
    },
    {
      name: 'hh-cabinet-staging',
      script: '/root/workspaces/projects/hh-scoring/services/cabinet.py',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: '.venv/bin/python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-cabinet-staging-error.log',
      out_file: '/root/.pm2/logs/hh-cabinet-staging-out.log'
    },
    {
      name: 'hh-dashboard-fastloop',
      script: '/root/workspaces/projects/hh-scoring/scripts/dashboard_fastloop.sh',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-dashboard-fastloop-error.log',
      out_file: '/root/.pm2/logs/hh-dashboard-fastloop-out.log'
    },
    {
      name: 'hh-hub-api',
      script: '/root/workspaces/projects/hh-scoring/services/hub_api.py',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: '.venv/bin/python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-hub-api-error.log',
      out_file: '/root/.pm2/logs/hh-hub-api-out.log'
    },
    {
      name: 'hh-import',
      script: '/root/workspaces/projects/arwox-biz/hr/hh-import/venv/bin/python',
      args: [
        '-m',
        'src.hh.import_with_notify'
      ],
      cwd: '/root/workspaces/projects/arwox-biz/hr/hh-import',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-import-error.log',
      out_file: '/root/.pm2/logs/hh-import-out.log'
    },
    {
      name: 'hh-litestream',
      script: '/root/workspaces/projects/hh-scoring/scripts/litestream-start.sh',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-litestream-error.log',
      out_file: '/root/.pm2/logs/hh-litestream-out.log'
    },
    {
      name: 'hh-pipeline',
      script: '/root/workspaces/projects/hh-scoring/scripts/pipeline_events.py',
      args: [
        '--loop'
      ],
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: '.venv/bin/python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      error_file: '/root/.pm2/logs/hh-pipeline-error.log',
      out_file: '/root/.pm2/logs/hh-pipeline-out.log'
    },
    {
      name: 'hh-pipeline-prod',
      script: '/root/workspaces/projects/hh-scoring-prod/scripts/pipeline_events.py',
      args: [
        '--loop'
      ],
      cwd: '/root/workspaces/projects/hh-scoring-prod',
      interpreter: 'python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-pipeline-prod-error.log',
      out_file: '/root/.pm2/logs/hh-pipeline-prod-out.log'
    },
    {
      name: 'hh-refetch',
      script: '/root/workspaces/projects/arwox-biz/hr/hh-import/venv/bin/python',
      args: [
        '-m',
        'src.hh.refetch_incomplete'
      ],
      cwd: '/root/workspaces/projects/arwox-biz/hr/hh-import',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-refetch-error.log',
      out_file: '/root/.pm2/logs/hh-refetch-out.log'
    },
    {
      name: 'hh-screening-monitor',
      script: '/root/workspaces/projects/hh-scoring/scripts/monitor_daemon.py',
      cwd: '/root/workspaces/projects/hh-scoring',
      interpreter: '.venv/bin/python',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-screening-monitor-error.log',
      out_file: '/root/.pm2/logs/hh-screening-monitor-out.log'
    },
    {
      name: 'hh-token-refresh',
      script: '/root/workspaces/projects/arwox-biz/hr/hh-import/venv/bin/python',
      args: [
        '-m',
        'src.hh.token_refresh'
      ],
      cwd: '/root/workspaces/projects/arwox-biz/hr/hh-import',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hh-token-refresh-error.log',
      out_file: '/root/.pm2/logs/hh-token-refresh-out.log'
    },
    {
      name: 'hh-wal-checkpoint',
      script: '/root/workspaces/projects/hh-scoring-prod/scripts/wal_checkpoint.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '*/10 * * * *',
      error_file: '/root/.pm2/logs/hh-wal-checkpoint-error.log',
      out_file: '/root/.pm2/logs/hh-wal-checkpoint-out.log'
    },
    {
      name: 'hr-bot-v2',
      script: '/root/workspaces/projects/arwox-biz/hr/bot/main.py',
      cwd: '/root/workspaces/projects/arwox-biz/hr/bot',
      interpreter: '/usr/bin/python3',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/hr-bot-v2-error.log',
      out_file: '/root/.pm2/logs/hr-bot-v2-out.log'
    },
    {
      name: 'kp-landing-serve',
      script: '/usr/bin/python3',
      args: [
        '-m',
        'http.server',
        '20081',
        '--bind',
        '0.0.0.0',
        '--directory',
        '/root/workspaces/projects/support-mvp-landing/dist'
      ],
      cwd: '/root',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/kp-landing-serve-error.log',
      out_file: '/root/.pm2/logs/kp-landing-serve-out.log'
    },
    {
      name: 'kpd-proxy',
      script: '/root/workspaces/projects/kpd-proxy/server.js',
      cwd: '/root/workspaces/projects/kpd-proxy',
      interpreter: 'node',
      exec_mode: 'cluster_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/kpd-proxy-error-67.log',
      out_file: '/root/.pm2/logs/kpd-proxy-out-67.log'
    },
    {
      name: 'kpi-event-handler',
      script: '/root/workspaces/projects/bitrix/kpi-manager/event-handler.js',
      cwd: '/root/workspaces/projects/bitrix/kpi-manager',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/kpi-event-handler-error.log',
      out_file: '/root/.pm2/logs/kpi-event-handler-out.log'
    },
    {
      name: 'load-governor',
      script: '/root/workspaces/projects/server-recovery/load-governor.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/load-governor-error.log',
      out_file: '/root/.pm2/logs/load-governor-out.log'
    },
    {
      name: 'margin-calc',
      script: '/usr/bin/bash',
      args: [
        '-c',
        'npx vite --host 0.0.0.0 --port 3333'
      ],
      cwd: '/root/workspaces/projects/arwox-b24-apps/margin-calc',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/margin-calc-error.log',
      out_file: '/root/.pm2/logs/margin-calc-out.log'
    },
    {
      name: 'memory-updater',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/memory-updater-daemon.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/memory-updater-error.log',
      out_file: '/root/.pm2/logs/memory-updater-out.log'
    },
    {
      name: 'minio-sync-worker',
      script: '/root/workspaces/projects/claude-state/minio-sync-worker.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/minio-sync-worker-error.log',
      out_file: '/root/.pm2/logs/minio-sync-worker-out.log'
    },
    {
      name: 'node-exporter',
      script: '/opt/node_exporter/node_exporter',
      args: [
        '--web.listen-address=127.0.0.1:9100',
        '--collector.textfile.directory=/var/lib/node_exporter/textfile/'
      ],
      cwd: '/root/workspaces/projects',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/node-exporter-error.log',
      out_file: '/root/.pm2/logs/node-exporter-out.log'
    },
    {
      name: 'pdf-decoder',
      script: '/root/workspaces/projects/pdf-decoder/server/index.js',
      cwd: '/root/workspaces/projects/pdf-decoder',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pdf-decoder-error.log',
      out_file: '/root/.pm2/logs/pdf-decoder-out.log'
    },
    {
      name: 'plan-lifecycle-manager',
      script: '/root/workspaces/tools/acc1-scripts/plan-lifecycle-manager.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '*/15 * * * *',
      error_file: '/root/.pm2/logs/plan-lifecycle-manager-error.log',
      out_file: '/root/.pm2/logs/plan-lifecycle-manager-out.log'
    },
    {
      name: 'pm2-api',
      script: '/root/workspaces/projects/pm2-panel/pm2-api.js',
      cwd: '/root/workspaces/projects/pm2-panel',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-api-error.log',
      out_file: '/root/.pm2/logs/pm2-api-out.log',
      env: {
        ...pm2ApiEnv
      }
    },
    {
      name: 'pm2-conductor',
      script: '/root/workspaces/tools/acc1-scripts/pm2-conductor.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-conductor-error.log',
      out_file: '/root/.pm2/logs/pm2-conductor-out.log'
    },
    {
      name: 'pm2-extended-metrics',
      script: '/root/workspaces/tools/acc1-scripts/pm2-extended-metrics.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-extended-metrics-error.log',
      out_file: '/root/.pm2/logs/pm2-extended-metrics-out.log'
    },
    {
      name: 'pm2-logrotate',
      script: '/root/.pm2/modules/pm2-logrotate/node_modules/pm2-logrotate/app.js',
      cwd: '/root/.pm2/modules/pm2-logrotate/node_modules/pm2-logrotate',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-logrotate-error.log',
      out_file: '/root/.pm2/logs/pm2-logrotate-out.log'
    },
    {
      name: 'pm2-loop-guard',
      script: '/root/workspaces/system/tools/scripts/pm2-loop-guard/guard.sh',
      cwd: '/root',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-loop-guard-error.log',
      out_file: '/root/.pm2/logs/pm2-loop-guard-out.log'
    },
    {
      name: 'pm2-prometheus-exporter',
      script: '/root/.pm2/modules/pm2-prometheus-exporter/node_modules/pm2-prometheus-exporter/exporter.js',
      cwd: '/root/.pm2/modules/pm2-prometheus-exporter/node_modules/pm2-prometheus-exporter',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/pm2-prometheus-exporter-error.log',
      out_file: '/root/.pm2/logs/pm2-prometheus-exporter-out.log'
    },
    {
      name: 'profile-rotation',
      script: '/root/workspaces/tools/acc1-scripts/profile-rotation.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 4 * * *',
      error_file: '/root/.pm2/logs/profile-rotation-error.log',
      out_file: '/root/.pm2/logs/profile-rotation-out.log'
    },
    {
      name: 'prometheus',
      script: '/opt/prometheus/prometheus',
      args: [
        '--config.file=/opt/prometheus/prometheus.yml',
        '--storage.tsdb.retention.time=30d',
        '--storage.tsdb.path=/opt/prometheus/data',
        '--web.listen-address=172.20.0.1:9090'
      ],
      cwd: '/opt/prometheus',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/prometheus-error.log',
      out_file: '/root/.pm2/logs/prometheus-out.log'
    },
    {
      name: 'redis-backup',
      script: '/root/workspaces/tools/acc1-scripts/redis-backup-daemon.sh',
      cwd: '/root/workspaces/tools/acc1-scripts',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/redis-backup-error.log',
      out_file: '/root/.pm2/logs/redis-backup-out.log'
    },
    {
      name: 'redis-exporter',
      script: '/opt/redis_exporter/redis_exporter',
      args: [
        '--web.listen-address=127.0.0.1:9121'
      ],
      cwd: '/root/workspaces/projects',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/redis-exporter-error.log',
      out_file: '/root/.pm2/logs/redis-exporter-out.log'
    },
    {
      name: 'redis-watchdog',
      script: '/root/workspaces/projects/server-recovery/redis-watchdog.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/redis-watchdog-error.log',
      out_file: '/root/.pm2/logs/redis-watchdog-out.log'
    },
    {
      name: 'sched-healthcheck',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/healthcheck-scheduler.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/sched-healthcheck-error.log',
      out_file: '/root/.pm2/logs/sched-healthcheck-out.log'
    },
    {
      name: 'sched-validator',
      script: '/root/workspaces/tools/acc1-scripts/sched-validator.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/sched-validator-error.log',
      out_file: '/root/.pm2/logs/sched-validator-out.log'
    },
    {
      name: 'search-quality-report',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/search-quality-report.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/search-quality-report-error.log',
      out_file: '/root/.pm2/logs/search-quality-report-out.log'
    },
    {
      name: 'security-scanner',
      script: '/root/workspaces/projects/security-scanner/scanner.js',
      cwd: '/root/workspaces/projects/security-scanner',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      error_file: '/root/.pm2/logs/security-scanner-error.log',
      out_file: '/root/.pm2/logs/security-scanner-out.log'
    },
    {
      name: 'session-indexer',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/session-indexer-daemon.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/session-indexer-error.log',
      out_file: '/root/.pm2/logs/session-indexer-out.log'
    },
    {
      name: 'session-merger',
      script: '/root/workspaces/tools/acc1-scripts/schedulers/session-merger-daemon.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/session-merger-error.log',
      out_file: '/root/.pm2/logs/session-merger-out.log'
    },
    {
      name: 'transcription-panel',
      script: '/root/workspaces/projects/client-video-transcription/admin/start-gunicorn.sh',
      cwd: '/root/workspaces/projects/client-video-transcription/admin',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/transcription-panel-error.log',
      out_file: '/root/.pm2/logs/transcription-panel-out.log'
    },
    {
      name: 'transcription-panel-dev',
      script: '/root/workspaces/projects/transcription-dev/admin/start-gunicorn.sh',
      cwd: '/root/workspaces/projects/transcription-dev/admin',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/transcription-panel-dev-error.log',
      out_file: '/root/.pm2/logs/transcription-panel-dev-out.log'
    },
    {
      name: 'tx-cleanup',
      script: '/root/workspaces/tools/acc1-scripts/tx-cleanup.sh',
      cwd: '/root/workspaces/projects',
      interpreter: 'bash',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      cron_restart: '0 3 * * *',
      error_file: '/root/.pm2/logs/tx-cleanup-error.log',
      out_file: '/root/.pm2/logs/tx-cleanup-out.log'
    },
    {
      name: 'yandex-reviews-backend',
      script: '/root/workspaces/projects/yandex/maps-reviews-autoresponder/backend/server.js',
      cwd: '/root/workspaces/projects/yandex/maps-reviews-autoresponder/backend',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/yandex-mvp-backend-error.log',
      out_file: '/root/.pm2/logs/yandex-mvp-backend-out.log'
    },
    {
      name: 'yubikey-v1',
      script: '/root/workspaces/projects/yubikey-v1/server/index.js',
      cwd: '/root/workspaces/projects/yubikey-v1',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: true,
      error_file: '/root/.pm2/logs/yubikey-v1-error.log',
      out_file: '/root/.pm2/logs/yubikey-v1-out.log'
    },
    {
      name: 'yubikey-v2',
      script: '/root/workspaces/projects/yubikey-v2/server/index.js',
      cwd: '/root/workspaces/projects/yubikey-v2',
      interpreter: 'node',
      exec_mode: 'fork_mode',
      instances: 1,
      autorestart: false,
      error_file: '/root/workspaces/projects/yubikey-v2/CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384',
      out_file: '/root/.pm2/logs/yubikey-v2-out.log'
    }
  ]
};
