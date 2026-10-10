# ТЗ dcfg-gcjsp — основная модель канала кода go: kimi-k2.7-code

## U1 — смена модели в `config/code-channel.json`
- `go.model`: `opencode-go/longcat-2.5-preview-free` → `opencode-go/kimi-k2.7-code`; `resume_model` остаётся `opencode-go/longcat-2.5-preview-free`.
- Основание: подписка OpenCode Go — фиксированная плата, модели списывают включённый лимит (https://opencode.ai/docs/go/ «Usage limits are defined as monthly dollar amounts»). Kimi K2.7 Code на Go: лимит $60/мес, ≈6 750 запросов/мес. longcat-free: 5 обрывов rc=124 из 26 прогонов (`state/code-channel/runs.jsonl`).
- Альтернатива glm-5.3 отклонена: лимит $15/мес, ≈1 080 запросов/мес.

## Приёмка
1) `code-channel --plan` → `go opencode-go/kimi-k2.7-code`.
2) Живой прогон `code-channel audit` → `run=0`, `model=opencode-go/kimi-k2.7-code`, `t<120`.
