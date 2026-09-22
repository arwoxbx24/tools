#!/usr/bin/env bash
set -euo pipefail

RESTIC=/root/workspaces/tools/bin/restic
TARGET=/
SNAP=latest
PHASE=
REPO_ENV=
PW_ENV=

usage() {
  cat <<'EOF'
Использование: restore.sh --phase <0-6|all> [параметры]
  --repo-env <файл>  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, RESTIC_REPOSITORY
  --pw-env <файл>    RESTIC_PASSWORD
  --snapshot <id>    снимок restic (по умолчанию latest)
  --target <dir>     каталог восстановления (по умолчанию /)
  --phase <0-6|all>  0: dry; 1: пакеты; 2: restic; 3: хост-БД;
                     4: docker; 5: pm2; 6: crontab; all: фазы 1-6
EOF
}

while (($#)); do
  case "$1" in
    -h|--help) usage; exit 1 ;;
    --repo-env|--pw-env|--snapshot|--target|--phase)
      (($# >= 2)) || { usage >&2; exit 1; }
      case "$1" in
        --repo-env) REPO_ENV=$2 ;;
        --pw-env) PW_ENV=$2 ;;
        --snapshot) SNAP=$2 ;;
        --target) TARGET=$2 ;;
        --phase) PHASE=$2 ;;
      esac
      shift 2
      ;;
    *) usage >&2; exit 1 ;;
  esac
done

[[ -n "$PHASE" ]] || { usage >&2; exit 1; }
case "$PHASE" in 0|1|2|3|4|5|6|all) ;; *) usage >&2; exit 1 ;; esac

STAGE="$TARGET/root/workspaces/system/tools/scripts/data/server-backup-stage"
MANIFESTS="$STAGE/manifests"

run_phase() {
  local phase=$1 compose latest_volume_backup archive volume package

  case "$phase" in
    1)
      echo '== Фаза 1: пакеты'
      echo "apt-get update; xargs -a $MANIFESTS/apt-manual.txt apt-get install -y"
      echo "pip3 install -r $MANIFESTS/pip-freeze.txt; pipx install из pipx.json"
      echo "npm install -g из npm-global.txt; snap install из snap.txt"
      apt-get update
      xargs -r -a "$MANIFESTS/apt-manual.txt" apt-get install -y
      pip3 install -r "$MANIFESTS/pip-freeze.txt"
      while IFS= read -r package; do
        [[ -n "$package" ]] && pipx install "$package"
      done < <(jq -r 'if type == "object" and has("venvs") then .venvs | keys[] elif type == "array" then .[] | if type == "string" then . else .package // .name // empty end else empty end' "$MANIFESTS/pipx.json")
      awk '$0 !~ /^(npm|corepack)$/' "$MANIFESTS/npm-global.txt" | xargs -r npm install -g
      while IFS= read -r package; do
        [[ -n "$package" ]] && snap install "$package"
      done < <(awk '$0 !~ /^(core.*|snapd|bare)$/' "$MANIFESTS/snap.txt")
      ;;
    2)
      echo '== Фаза 2: restic'
      echo "source $REPO_ENV; source $PW_ENV; $RESTIC restore $SNAP --target $TARGET"
      if [[ ! -x "$RESTIC" ]]; then
        echo "RESTIC не найден: $RESTIC" >&2
        echo 'Скачайте restic 0.19.1 из GitHub Releases, затем сверяйте архив с SHA256SUMS:' >&2
        echo 'https://github.com/restic/restic/releases/download/v0.19.1/restic_0.19.1_linux_amd64.bz2' >&2
        echo 'sha256sum restic_0.19.1_linux_amd64.bz2; grep restic_0.19.1_linux_amd64.bz2 SHA256SUMS' >&2
        return 1
      fi
      [[ -r "$REPO_ENV" && -r "$PW_ENV" ]] || { echo 'Для restic нужны --repo-env и --pw-env.' >&2; return 1; }
      set -a
      source "$REPO_ENV"
      source "$PW_ENV"
      set +a
      "$RESTIC" restore "$SNAP" --target "$TARGET"
      ;;
    3)
      echo '== Фаза 3: хост-БД'
      echo "gunzip -c $STAGE/host-db/pg_dumpall.sql.gz | su - postgres -c 'psql -f -'"
      echo 'systemctl stop redis-server; cp redis-dump.rdb /var/lib/redis/dump.rdb; chown redis:redis; systemctl start redis-server'
      echo 'systemctl stop grafana-server; cp grafana.db /var/lib/grafana/grafana.db; chown grafana:grafana; systemctl start grafana-server'
      su - postgres -c 'psql -f -' < <(gunzip -c "$STAGE/host-db/pg_dumpall.sql.gz")
      systemctl stop redis-server
      cp "$STAGE/host-db/redis-dump.rdb" /var/lib/redis/dump.rdb
      chown redis:redis /var/lib/redis/dump.rdb
      systemctl start redis-server
      systemctl stop grafana-server
      cp "$STAGE/host-db/grafana.db" /var/lib/grafana/grafana.db
      chown grafana:grafana /var/lib/grafana/grafana.db
      systemctl start grafana-server
      ;;
    4)
      echo '== Фаза 4: docker'
      echo "docker compose up -d для $TARGET/root/workspaces/system/services/*/"
      echo "тома из $TARGET/root/backups/docker/<последний>/*.tar.gz"
      for compose in "$TARGET"/root/workspaces/system/services/*/; do
        if [[ -f "${compose}docker-compose.yml" ]]; then
          docker compose -f "${compose}docker-compose.yml" up -d
        elif [[ -f "${compose}compose.yml" ]]; then
          docker compose -f "${compose}compose.yml" up -d
        fi
      done
      latest_volume_backup=$(find "$TARGET/root/backups/docker" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)
      [[ -n "$latest_volume_backup" ]] || { echo 'Не найден снимок docker-томов.' >&2; return 1; }
      for archive in "$TARGET/root/backups/docker/$latest_volume_backup"/*.tar.gz; do
        [[ -f "$archive" ]] || continue
        volume=$(basename "${archive%.tar.gz}")
        case "$volume" in bindmount_*|*.sql.gz|*.archive.gz) continue ;; esac
        docker volume create "$volume"
        tar -xzf "$archive" -C "/var/lib/docker/volumes/$volume/_data"
      done
      ;;
    5)
      echo '== Фаза 5: pm2'
      echo "pm2 resurrect $TARGET/root/.pm2/dump.pm2"
      pm2 resurrect "$TARGET/root/.pm2/dump.pm2"
      ;;
    6)
      echo '== Фаза 6: crontab'
      echo "crontab $STAGE/crontab-root.txt"
      crontab "$STAGE/crontab-root.txt"
      ;;
  esac
}

if [[ "$PHASE" == 0 ]]; then
  echo '== Фаза 0: dry'
  echo '== Фаза 1: пакеты из manifests'
  echo '== Фаза 2: restic restore снимка'
  echo '== Фаза 3: PostgreSQL, Redis и Grafana'
  echo '== Фаза 4: docker compose и тома'
  echo '== Фаза 5: pm2 resurrect'
  echo '== Фаза 6: crontab root'
  exit 0
fi

CURRENT_PHASE=$PHASE
trap 'exit "$CURRENT_PHASE"' ERR

if [[ "$PHASE" == all ]]; then
  for PHASE in 1 2 3 4 5 6; do
    CURRENT_PHASE=$PHASE
    run_phase "$PHASE"
    [[ "$PHASE" == 6 ]] || read -r -p 'Продолжить следующую фазу? ' _
  done
else
  run_phase "$PHASE"
fi
