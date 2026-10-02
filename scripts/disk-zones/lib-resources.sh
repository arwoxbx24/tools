#!/bin/bash
# lib-resources.sh — сторож ресурсов для ночного запуска зон (spec:090, ADR-090-9).
# Функция dz_resources_ok → rc 0, если достаточно памяти, CPU и места на /.
# Источники переопределяемы для теста: DZ_MEMINFO, DZ_LOADAVG, DZ_DF_ROOT.
# Только bash + awk + df.

dz_resources_ok() {
  local meminfo=${DZ_MEMINFO:-/proc/meminfo}
  local loadavg_src=${DZ_LOADAVG:-/proc/loadavg}
  local df_root=${DZ_DF_ROOT:-/}
  local min_mem_pct=${DZ_MIN_MEM_PCT:-15}
  local max_load_ratio=${DZ_MAX_LOAD_RATIO:-0.6}
  local min_free_mb=${DZ_MIN_FREE_MB:-1024}
  local ncpu

  ncpu=$(nproc 2>/dev/null || echo 1)
  [ "$ncpu" -ge 1 ] 2>/dev/null || ncpu=1

  # 1. Память: MemAvailable >= min_mem_pct% от MemTotal (kB). Нет данных -> fail.
  awk -v pct="$min_mem_pct" '
    /^MemTotal:/     { t = $2 }
    /^MemAvailable:/ { a = $2 }
    END { exit !( t > 0 && a >= t * pct / 100 ) }
  ' "$meminfo" || return 1

  # 2. Нагрузка: loadavg1 < max_load_ratio * nproc. Нет данных -> fail.
  awk -v n="$ncpu" -v r="$max_load_ratio" '
    NR == 1 { ok = ($1 < r * n); found = 1 }
    END { exit !(found && ok) }
  ' "$loadavg_src" || return 1

  # 3. Свободно на корне >= min_free_mb (df -P => KiB, /1024 => MB). Нет строки -> fail.
  df -P "$df_root" 2>/dev/null | awk -v min="$min_free_mb" '
    NR == 2 { ok = ($4 / 1024 >= min); found = 1 }
    END { exit !(found && ok) }
  ' || return 1

  return 0
}
