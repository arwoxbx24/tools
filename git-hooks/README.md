# git-hooks: общий gitleaks-диспетчер и цепочка клиентских git-хуков.

dispatch — единая точка входа: pre-push сканирует отправляемые коммиты через gitleaks, остальные хуки диспетчер не сканирует, а только цепочит.

Включение: строка `hooksPath = /root/workspaces/tools/git-hooks` в секции `[core]` файла `/etc/gitconfig`.

Хуки репо (например `<repo>/.git/hooks/<имя>`) вызываются цепочкой через dispatch, сохраняя свой stdin и аргументы.

Откат: удалить строку hooksPath из секции `[core]` в `/etc/gitconfig`.
