# ТЗ dcfg-1ci20.13 V1 — запасной приёмник форм на нашем сервере (spec:103 v3, ADR-103-21)

Исполнитель пишет код сам, `code-channel` не вызывает. Разведка — repowise (для tools индекса нет → `grep -n`).

## Цель
При сбое Яндекса заявки arwox.ru принимает наш сервер тем же кодом, что функция Яндекса (`index.py` + `consent.py`), без переписывания логики.

## Границы
- Новый файл `scripts/forms-backup/server.py` (python3 stdlib, `http.server` + `ThreadingHTTPServer`, ≤80 строк). Других файлов не трогать.
- Код обработчика не копировать: путь каталога функции — аргумент/переменная `FORMS_HANDLER_DIR` (по умолчанию `/root/workspaces/projects/arwox-v3-src/site78-releases/2026-07-29/backend-arwox-lead-form`), `sys.path.insert(0, dir)` → `import index` → `index.handler(event, None)`.
- Слушать `FORMS_BACKUP_BIND` (по умолчанию `172.17.0.1`) : `FORMS_BACKUP_PORT` (по умолчанию `20140`). Наружу порт не открывать.
- Перевод запроса в event Yandex Functions (поля, которые читает обработчик: `index.py:170-187`, `consent.py:106-114`):
  `httpMethod`, `headers` (все заголовки запроса как dict), `body` (str; бинарное — base64 + `isBase64Encoded: true`), `isBase64Encoded`, `queryStringParameters` (dict из query), `path`.
  Заголовок `X-Real-Remote-Address` = значение `X-Real-IP` от прокси (Nginx Proxy Manager ставит его сам); входящий `X-Real-Remote-Address` от клиента перезаписывается.
- Ответ: `statusCode`, `headers` (dict), `body` (если `isBase64Encoded` — декодировать) → HTTP-ответ.
- Ошибка обработчика → 502 и строка в stderr без тела запроса (ПДн).
- Секреты: процесс получает env от pm2 (`WEBHOOK_URL`, `SMARTCAPTCHA_SECRET`, `SMARTCAPTCHA_SITEKEY`, `SELF_URL`); файл секретов не читать, значения не печатать, тела запросов не логировать.
- Запрещено: правка `index.py`/`consent.py`, правка `ecosystem.config.js` (делает Claude отдельно), сеть в тесте.

## Тест (один файл `scripts/forms-backup/server-test.py`, ≤60 строк, без сети)
Временный каталог с заглушкой `index.py` (`handler` возвращает event-поля в body JSON и `statusCode 302`, `Location`). Запустить `server.py` на 127.0.0.1:случайный порт с `FORMS_HANDLER_DIR` = заглушка:
1. `GET /?a=1` → 302, `Location` проброшен; в event `httpMethod=GET`, `queryStringParameters.a=1`.
2. `POST /` с `NAME=x&PHONE=1` и `X-Real-IP: 9.9.9.9`, `X-Real-Remote-Address: 6.6.6.6` → в event `body` содержит `NAME=x`, `headers["X-Real-Remote-Address"] == "9.9.9.9"`.
3. Заглушка бросает исключение → 502.
Печать `PASS 3/3`.

## Критерии приёмки
1. `python3 -m py_compile scripts/forms-backup/server.py` → rc 0; `wc -l` ≤ 80.
2. `python3 scripts/forms-backup/server-test.py` → `PASS 3/3`, rc 0.
3. `grep -nE "print\(.*body|WEBHOOK_URL.*print" scripts/forms-backup/server.py` → 0.

## Паспорт источников
- Контракт события HTTP-функции Яндекса (поля `httpMethod`, `headers`, `body`, `isBase64Encoded`, `queryStringParameters`): https://yandex.cloud/ru/docs/functions/concepts/function-invoke — проверить по документации при сомнении.
- Обработчик: `arwox-v3-src/site78-releases/2026-07-29/backend-arwox-lead-form/index.py:170-187` (`_body_params`, `_header`, `handler`), `consent.py:106-114` (IP из `X-Real-Remote-Address`, правый край `X-Forwarded-For`).
- stdlib: https://docs.python.org/3/library/http.server.html
