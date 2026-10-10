# ТЗ dcfg-9pcll — основная модель канала кода go: glm-5.3-flash

## U1 — `config/code-channel.json`
- `go.model`: `opencode-go/longcat-2.5-preview-free` → `opencode-go/glm-5.3-flash`; `resume_model` остаётся `opencode-go/longcat-2.5-preview-free`.
- Основание: владелец 11.10 — нужна скорость; бесплатные модели рвутся, перезапуски тратят токены Claude.
- Замер: `code-channel audit` glm-5.3-flash `run=0 t=35`; kimi-k2.7-code `run=0 t=50`.
- Цена (https://opencode.ai/docs/go/): GLM-5.3-Flash $0.15 вход / $0.50 выход / $0.03 кэш за 1M, лимит Go $60/мес. 200M токенов в пропорциях проекта ≈ $9.
- Отклонено: kimi-k2.7-code ≈ $60 на 200M; mimo-v2.6-flash 22/45 rc=124; deepseek-v4.1-flash — «This Go model requires Global regions»; Muse Spark — обучение на промптах.

## Приёмка
1) `code-channel --plan` → `go opencode-go/glm-5.3-flash`.
