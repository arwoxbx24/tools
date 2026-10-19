# TZ dcfg-yb2ys — vpn-route-check: Windows-скрипт проверки маршрутов VPN (Clash Verge / Hiddify), отчёт на сервер

FILE: scripts/vpn-route-check/vpn-route-check.ps1
FILE: scripts/vpn-route-check/START.cmd
FILE: scripts/vpn-route-check/README.md

Executor: sdk-agent code. Три файла создаются целиком (old "" — файлов `.ps1`/`.cmd` нет; README.md существует с одной строкой `# placeholder` — заменить её). Ничего другого в репо не трогать.

## Назначение
Владелец (не разработчик, Windows 10/11, VPN-программа Clash Verge Rev или Hiddify для Windows — версия любая) двойным кликом запускает `START.cmd`. Скрипт сам находит локальный API ядра (Clash API / mihomo) и локальный прокси-порт, прогоняет контрольный список сайтов, читает из потока логов ядра, по какому правилу и в какую группу ушёл каждый сайт, меряет время ответа, затем 60 секунд пассивно пишет маршруты обычного сёрфинга владельца, сохраняет отчёт на рабочий стол и отправляет его на наш сервер (MinIO, presigned POST-форма из `upload.json` рядом со скриптом). Никаких паролей, cookie и содержимого трафика — только имена хостов, правило, группа, миллисекунды.

## START.cmd (CRLF, cp866-безопасно: только ASCII)
```
@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0vpn-route-check.ps1"
pause
```

## vpn-route-check.ps1 — требования (PowerShell 5.1 совместимый, без модулей; `[Console]::OutputEncoding = [Text.Encoding]::UTF8` первой строкой после параметров; весь текст на экране — по-русски)

Параметры: `[switch]$SelfTest`, `[int]$PassiveSeconds = 60`.

1. **Список хостов** (константа): RU — `gosuslugi.ru, sberbank.ru, avito.ru, mail.ru, yandex.ru, vk.com, 2gis.com, habr.com, ozon.ru, wildberries.ru, dzen.ru, rutube.ru, kinopoisk.ru, bitrix24.ru, xn--d1abbgf6aiiy.xn--p1ai` (= президент.рф); зарубежные — `github.com, google.com, youtube.com, wikipedia.org, cloudflare.com`. Для каждого хоста хранить `expected` = `direct` для RU, `vpn` для зарубежных.

2. **Поиск API ядра**: кандидаты `127.0.0.1:9097` (Clash Verge Rev, по умолчанию), `127.0.0.1:9090`, `127.0.0.1:16756` (Hiddify). Секреты-кандидаты: пустой; значение `secret:` из `$env:APPDATA\*clash-verge*\config.yaml` (Get-ChildItem -Recurse -Filter config.yaml, первая строка `^\s*secret:\s*(.+)$`, кавычки снять); значения `"secret"` из `*.json` под `$env:APPDATA\*hiddify*` и `$env:LOCALAPPDATA\*hiddify*` (Select-String `"secret"\s*:\s*"([^"]+)"`). Для каждой пары (порт, секрет): `GET http://host/version` с заголовком `Authorization: Bearer <secret>` (без заголовка при пустом), таймаут 2 с; код 200 → API найден, запомнить base, секрет, тело `/version`. Не найден → в отчёте `api: null`, скрипт продолжает (замеры времени всё равно делаются).

3. **Поиск прокси-порта**: кандидаты `7897, 7890, 12334, 1080, 2080` на 127.0.0.1 — `System.Net.Sockets.TcpClient` ConnectAsync с ожиданием 500 мс; первый открытый. Не найден → `proxy_port: null`, замер через прокси пропускается.

4. **Поток логов** (только если API найден): `GET <base>/logs?level=info` — это HTTP chunked-поток строк JSON `{"type":"info","payload":"..."}`. Читать в фоне через `Start-Job`, передавая base, секрет и путь файла `$env:TEMP\vpn-route-check-logs.txt`: в job — `[System.Net.HttpWebRequest]::Create(url)`, заголовок Authorization, `GetResponse().GetResponseStream()`, `StreamReader.ReadLine()` в цикле, каждую строку `Add-Content` в файл. Перед стартом файл удалить. Главный поток ждёт 1 с после старта job.

5. **Активные пробы** для каждого хоста по очереди (всего ≤ 20):
   - через прокси (если порт найден): `Invoke-WebRequest -Uri "https://<host>/" -Method Head -Proxy "http://127.0.0.1:<port>" -TimeoutSec 8 -MaximumRedirection 0 -UseBasicParsing`; `Stopwatch` → `proxy_ms`; любой HTTP-ответ (включая 3xx/4xx/5xx из `$_.Exception.Response`) считается успехом связи; таймаут/ошибка сокета → `proxy_ms: null`, `proxy_err: <короткий текст>`.
   - напрямую, минуя прокси: то же с `-Proxy $null` и `-NoProxy`-семантикой для 5.1: использовать `[System.Net.WebRequest]::Create()` с `.Proxy = $null`, Method HEAD, Timeout 8000 → `direct_ms`/`direct_err` (в режиме TUN это тоже пойдёт через ядро — отметить в README).
   - Между хостами пауза 200 мс.

6. **Пассивная фаза**: вывести «Теперь 60 секунд просто ходите по своим обычным сайтам в браузере…», обратный отсчёт по 10 с, `Start-Sleep`.

7. **Разбор логов**: остановить job (`Stop-Job`, `Remove-Job`), прочитать файл. Для каждой строки взять `payload` (разобрать JSON через `ConvertFrom-Json`, при ошибке — regex `"payload":"(.*)"`). Регулярное выражение mihomo: `-->\s+(?<host>[^:\s]+):\d+\s+match\s+(?<rule>[^\s]+(?:\([^)]*\))?)\s+using\s+(?<chain>.+)$`; `group` = первый элемент chain до `[`, обрезать пробелы. Также `-->\s+(?<host>[^:\s]+):\d+\s+(?<rule>No match|DIRECT|error)` → rule как есть. Хосты из контрольного списка сопоставлять по точному совпадению или суффиксу `.<host>`; все остальные — в `passive` (уникальные host → rule, group, count).

8. **Вердикт** для каждого контрольного хоста: `group` содержит `DIRECT` или `Россия` (регистр не важен) → `route: direct`; группа найдена и не direct → `route: vpn`; REJECT → `route: reject`; не найдено в логах → `route: unknown`. `ok = (route -eq expected)`; при `unknown` — `ok: null`.

9. **Отчёт**: объект `{ts (ISO 8601 UTC), computer: $env:COMPUTERNAME, os: [Environment]::OSVersion.VersionString, api: {base, version_body} | null, proxy_port, hosts: [ {host, expected, route, ok, rule, group, proxy_ms, proxy_err, direct_ms, direct_err} ], passive: [ {host, rule, group, count} ], log_lines: <число строк> }`. Сохранить `ConvertTo-Json -Depth 6` в `"$([Environment]::GetFolderPath('Desktop'))\vpn-route-check-<yyyyMMdd-HHmmss>.json"`. На экран — таблица `Format-Table host, expected, route, ok, group, rule, proxy_ms, direct_ms` и две итоговые строки: `РФ напрямую: N из M`, `Зарубеж через VPN: N из M`; список хостов с `ok = $false` или `unknown` отдельно.

10. **Отправка**: если рядом со скриптом есть `upload.json` вида `{ "url": "https://io.b244.ru/files/", "fields": { "key": "...", "policy": "...", "x-amz-algorithm": "...", ... } }` — собрать multipart/form-data: все `fields` как текстовые части в указанном порядке, последней часть `file` с содержимым JSON-отчёта (`filename="report.json"`, `Content-Type: application/json`), отправить `POST` через `Invoke-WebRequest -Method Post -ContentType "multipart/form-data; boundary=<b>" -Body <bytes>` (тело собрать вручную в `[byte[]]` UTF-8, CRLF, без BOM; `-Proxy $null`). Код 2xx → «Отчёт отправлен на сервер», иначе — код и первые 300 символов ответа; при любой ошибке отправки скрипт не падает, файл на рабочем столе остаётся. `upload.json` нет → «Отправка пропущена: нет upload.json».

11. `-SelfTest`: без сети и без job: прогнать разбор (п.7–8) на встроенном массиве из 4 строк-образцов (`… --> habr.com:443 match GeoIP(ru) using DIRECT`, `… --> github.com:443 match Match using VPN[VLESS-ws]`, `… --> 2gis.com:443 match DomainSuffix(2gis.com) using 🇷🇺 Россия напрямую`, `… --> youtube.com:443 match DstPort(443) using REJECT`) и вывести `SELFTEST OK` при ожидаемых `direct, vpn, direct, reject`, иначе `SELFTEST FAIL` и `exit 1`. Все функции (поиск API, разбор, отчёт, отправка) — отдельные `function`, чтобы SelfTest вызывал только разбор.

12. Стиль: `Set-StrictMode -Version 2`, `$ErrorActionPreference = 'Continue'` внутри проб, `try/catch` вокруг каждой сетевой операции, ни один сбой одного хоста не прерывает прогон (`continue`). Без `Write-Host` цветов кроме итоговых строк (зелёный/красный). Размер ≤ 260 строк.

## README.md (заменить `# placeholder`)
Коротко по-русски: что делает, как запустить (двойной клик START.cmd при включённом VPN, 1–2 минуты, окно не закрывать), что уходит на сервер (список хостов, правило, группа, мс; ничего личного), где лежит отчёт (рабочий стол), что означает TUN-режим для `direct_ms`, как агент читает результат: `mc cp b244share/files/vpn-route-check/result.json .` и `upload.json` генерируется `mc share upload --json --expire 72h b244share/files/vpn-route-check/result.json` (поля формы — из `share`), самопроверка `pwsh -File vpn-route-check.ps1 -SelfTest`.
