# lib-compress.sh — сжатие файла zstd с проверкой целостности (FR-090-04).
# Библиотека (source), функция dz_compress <файл> сжимает файл в <файл>.zst,
# проверяет целостность (тест архива, sha256, размер/mtime) и только при
# успехе удаляет оригинал. При любой ошибке шагов 3-6 удаляется только .zst.

dz_compress() {
  local f=${1:-}
  local out lrc before size mtime now now_size now_mtime
  local dhash chash after_size

  # 1. Файл не должен быть открыт ни одним процессом.
  out=$(lsof -- "$f" 2>/dev/null)
  lrc=$?
  if [ "$lrc" -eq 0 ] && [ -n "$out" ]; then
    echo busy
    return 3
  fi
  if [ "$lrc" -ne 1 ] || [ -n "$out" ]; then
    echo lsof-error
    return 4
  fi

  # 2. Размер и mtime до сжатия.
  before=$(stat -c '%s %Y' -- "$f")
  size=${before%% *}
  mtime=${before##* }

  # 3. Сжать в $f.zst, оригинал оставить.
  if ! zstd -q -k -o "$f.zst" -- "$f" 2>/dev/null; then
    rm -f -- "$f.zst"
    echo compress-verify-fail
    return 2
  fi

  # Тестовые крючки (только для selfcheck): порча архива / мутация оригинала.
  if [ "${DZ_TEST_CORRUPT:-0}" = 1 ]; then printf x >>"$f.zst"; fi
  if [ "${DZ_TEST_MUTATE:-0}" = 1 ]; then printf x >>"$f"; fi

  # 4. Проверка целостности архива.
  if ! zstd -q -t -- "$f.zst" 2>/dev/null; then
    rm -f -- "$f.zst"
    echo compress-verify-fail
    return 2
  fi

  # 5. Распакованный архив == оригинал.
  dhash=$(zstd -q -dc -- "$f.zst" 2>/dev/null | sha256sum | awk '{print $1}')
  chash=$(sha256sum "$f" | awk '{print $1}')
  if [ "$dhash" != "$chash" ]; then
    rm -f -- "$f.zst"
    echo compress-verify-fail
    return 2
  fi

  # 6. Размер и mtime не изменились.
  now=$(stat -c '%s %Y' -- "$f")
  now_size=${now%% *}
  now_mtime=${now##* }
  if [ "$now_size" != "$size" ] || [ "$now_mtime" != "$mtime" ]; then
    rm -f -- "$f.zst"
    echo compress-verify-fail
    return 2
  fi

  # 7. Всё успешно: удалить оригинал.
  after_size=$(stat -c '%s' -- "$f.zst")
  rm -f -- "$f"
  echo "ok $size $after_size"
  return 0
}
