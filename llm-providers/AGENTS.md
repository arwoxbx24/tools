# tools/llm-providers AGENTS — direct OpenRouter worker contract

Scope: Files under `tools/llm-providers/*` and any task routed through these workers.
Primary source of truth for runtime behavior is `tools/llm-providers/model-policy.json`.

## Required execution contract (must hold before any call)
- Read `tools/llm-providers/model-policy.json` (or synced mirror `models.yaml`) before usage.
- Prompt language must be English for all model inputs.
- Preflight must be offline and pass before every run (no model/network calls): verify policy file parse, route resolution, role mapping, and cost cap.
- Exactly one author call and exactly one independent review call are required; author and review MUST use different models.
- All required tests must be runnable from this scope and run before completion.
- Logging/receipt is mandatory and must be redacted: include timestamp, role, model, request id hash, status, reason, finish reason, token counts, cost, latency; never include prompts, API keys, or secrets.

## Route and model constraints
- Transport: direct OpenRouter only, through `openrouter_direct` adapter.
- Base URL env: `OPENROUTER_BASE_URL` (default `https://openrouter.ai/api/v1`).
- Auth: `OPENROUTER_API_KEY` required.
- Endpoint: `/chat/completions`.
- Forbidden: direct API bypasses, direct OpenAI/Anthropic/GLM/Kimi endpoints, uncontrolled swarms, and any `kimi-swarm` fallback.
- Role routes must follow policy:
  - generate → `code`
  - review / second-opinion / analyze / architect-draft / hard-debug → `review`
  - classify / moderate / format-check → `validation`

## Safety and behavior prohibitions
- No prod, DB, or HH side effects from worker flows.
- No production deploys or state changes from provider tasks.
- No historical-context files (`archive`, `history`, `legacy`, `snapshot`, etc.) as context sources.
- No retry attempts after malformed/invalid model output.
- Do not emit, store, or replay full user prompts or outputs from past tasks as training/continuation context.
- Do not run git commits or pushes from this worker path.
- No direct `POST` send paths that bypass `hhkit.send_message`.
- If any mandatory gate fails, execution is blocked.

## Allowed outcomes
- Success requires:
  - offline preflight PASS,
  - one author call,
  - one review call with a different model,
  - runnable tests passing,
  - redacted receipt produced.
