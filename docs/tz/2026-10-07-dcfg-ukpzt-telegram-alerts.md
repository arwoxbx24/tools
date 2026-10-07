# ТЗ dcfg-ukpzt — достоверные Telegram-уведомления

## U1

Owner: Codex. Scope: `bin/pm2-loop-guard`, `scripts/disk-rotate.sh`,
`scripts/schedulers/ags-search-watch.sh` and their existing stub tests.

Ten notifications from 05–06.10 must be classified using current PM2, disk,
zone ledger, backup log, and Beads evidence. Record ten rows in the atom notes.
Do not operate hh services, stop processes, send Telegram messages, read
secrets, or run heavy live tests during the day.

An alert may say `Чинит агент` only when it includes an open Beads atom ID for
that event. Without such a binding, use `Нужен атом`. Keep the existing alert
types. A repeated condition sends once until an observed recovery; a recovery
message requires the same PM2 service to be online. Keep failed deliveries in
the existing pending queue.

Acceptance: one small stub run, shell syntax and diff checks, zero bare
`Чинит агент` in the three sources, ten evidence rows, and merged PR through
`ship-post --submit`. Current problems outside these three sources get their
own discovered-from atoms. Rollback is the U1 commit; runtime alert-state
files retain the previous values and no live notification is sent for this TZ.
