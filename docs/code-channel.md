# Code Channel

`bin/code-channel` is the supported code-writing route for Claude and Codex. Callers do not invoke bare `opencode run` or `codex exec`.

## Invocation

- `bin/code-channel auto <absolute-worktree> <absolute-task-file>` runs enabled providers in order.
- `bin/code-channel audit <absolute-worktree> <absolute-task-file>` runs a read-only audit and rejects a changed worktree.
- `bin/code-channel <id> <absolute-worktree> <absolute-task-file> [--model <model>]` selects one enabled provider.
- `bin/code-channel --plan` prints the enabled route; `--help` prints syntax and paths.

Use the task's isolated worktree and keep its task file inside that worktree. Do not bypass an `external_directory` denial by granting broad access. The executor must not call Code Channel recursively or make Git commits; the coordinator owns task state and delivery.

## Provider route and limits

`config/code-channel.json` currently enables `go` (`opencode-go/glm-5.3-flash`) and then `codex` (profile model, high reasoning effort). OpenRouter, Bitrix GPT, and Kimi are disabled. The configured Go `audit_model` is `opencode-go/longcat-2.5-preview-free`. `resume_model` remains in the configuration for compatibility but the current wrapper does not resume a timed-out OpenCode session. Change enabled providers or paid models only with owner authorization. Always inspect the live route with `bin/code-channel --plan`.

OpenCode Go is a subscription with included usage, not unlimited capacity: the [official Go documentation](https://opencode.ai/v2/docs/console/go) describes Go and Go Plus usage tiers. Local code cannot remove provider quotas or account limits. A provider denial or quota failure must be reported with its actual exit and journal receipt.

Each OpenCode attempt has a 590-second safety bound. In `auto`, an OpenCode exit `124` switches to the next enabled provider only when the worktree is unchanged. If the timed-out attempt left edits, Code Channel returns `124` and preserves them for inspection. Other terminal exit codes `3`, `5`, `15`, `22`, and `24` stop the route. Exit `0` with no code changes may try the next provider; the last provider returns its actual exit or `16` for no changes. Audit accepts exit `0` only when the worktree remains unchanged.

The [official CLI documentation](https://opencode.ai/v2/docs/cli) documents `opencode run` for non-interactive tasks; the consulted CLI page does not specify a batch option for this route. Do not invent one. [OpenCode session warming](https://opencode.ai/v2/docs/warming) is disabled by default and sends periodic model requests to keep short-lived caches warm. It is left disabled here because the route has no measured idle-cache benefit that justifies extra requests.

## Exit codes and receipts

| Exit | Meaning |
| --- | --- |
| `0` | The selected operation passed its wrapper checks. |
| `3`, `5`, `15` | Invalid/disabled provider, setup, or model gate; inspect stderr. |
| `16` | Code route produced no changes. |
| `21`, `24` | Codex execution or read-only environment failure; inspect stderr. |
| `22` | Audit changed the worktree. |
| `23` | Provider reconciliation failed. |
| `30` | Recursive Code Channel invocation. |
| `124` | OpenCode reached its 590-second bound; inspect preserved edits. |

Other exits retain their numeric code and stderr. The local journal is `state/code-channel/runs.jsonl`; check `provider_expected`, `provider_actual`, `rc`, and the run ID before declaring an outcome. A tool receipt proves execution, not semantic correctness. Use the task's acceptance check on its real input.

## U1 Timeout continuation acceptance

Owner atom: `tools-fjs`. Scope: the existing `bin/code-channel`, `bin/code-channel-test`, and this page. The change retains the 590-second bound and all host/provider gates. The regression suite must show a Go `124` without edits invoking Codex and a Go `124` with partial edits stopping without Codex. `bash bin/code-channel-test` prints `PASS 55/55`; `bin/code-channel --plan` prints Go then Codex. A real isolated code task must produce a scoped diff and a matching journal row. Rollback restores these three owned files in the isolated worktree; never discard another agent's edits.
