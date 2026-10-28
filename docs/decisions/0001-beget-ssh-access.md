# 0001 — SSH-доступ агентов к хостингу Beget

## Контекст
Агентам нужно выполнять команды на shared-хостинге Beget владельца по SSH. Учётные данные не должны попадать в env/argv процессов.
Секция аккаунта Beget.API предлагает только `getAccountInfo` и `toggleSsh`, метода для ключей нет: https://beget.com/ru/kb/api/funkczii-upravleniya-akkauntom.
Формат из доков Beget — host `<login>.beget.tech`, user `<login>`, установка ключа через `authorized_keys`: https://beget.com/ru/kb/how-to/ssh/avtomaticheskaya-ssh-avtorizacziya-po-klyuchu.

## Выбор
Один read-first wrapper `bin/beget-ssh`; отдельный ed25519-ключ `/root/workspaces/secrets/projects/beget_ssh_ed25519` (600), known_hosts — `/root/workspaces/secrets/projects/beget_ssh_known_hosts`.
`beget-ssh init` печатает ОДНУ строку, владелец один раз вставляет её в живую SSH-вкладку Beget, которая идемпотентно дописывает pubkey в `~/.ssh/authorized_keys`.
ssh с `IdentitiesOnly=yes`, `BatchMode=yes`, `ConnectTimeout=15`, `StrictHostKeyChecking=accept-new`, `UserKnownHostsFile=/root/workspaces/secrets/projects/beget_ssh_known_hosts`.
`check` выполняет `php -v | head -1`.

## Отклонённые варианты
Пароль через sshpass из beget.env — пароль утекает в env/argv процесса, отзыва ключа по строке нет.
Ключ в `~/.ssh` — запрещён правилами сервера и смешивается с серверными ключами.
Только Beget.API — метода ключей нет, лишь `getAccountInfo` и `toggleSsh` (URL выше).

## Последствия
Владелец один раз вставляет строку из `init`.
Откат: вставить вывод `revoke-line` и безопасно удалить ключ и known_hosts (`/root/workspaces/secrets/projects/beget_ssh_ed25519`, `/root/workspaces/secrets/projects/beget_ssh_known_hosts`) через `/root/workspaces/tools/bin/safe-delete ...`.
Утёкший ключ закрывается `revoke-line` (удаляет все строки `authorized_keys` с тегом ` agent-beget-`) и перегенерацией через `init`.
